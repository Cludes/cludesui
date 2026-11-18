if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  Themed Character Sheet
--------------------------------------------------------------------------------
local ADDON_NAME, mod = ...
local L = _G.CludesUI and _G.CludesUI.L or function(keyName)
    return keyName
end
local skinned = false
local issecretvalue = issecretvalue or function()
    return false
end

-- External weak-keyed lookup table for frame state (prevents tainting Blizzard frames)
local FFD, GetFFD = CludesUI.NewFrameData()

-- The Character Sheet card's style: "blizzard" for Blizz Default, else "cui"
-- (CludesUI and Modern skin the sheet alike). Account-wide, swapped with
-- the whole-UI look (CludesUI.SwapWindowSkinStyle), and latched on the
-- first read for the session, which comes at PLAYER_LOGIN after the look is
-- reconciled (a change reloads). Blizz Default is Blizzard's own character
-- frame with the CludesUI stats section inside its stats pane and the
-- item level / enchant / upgrade-track text beside its slots; on WoW Forever
-- it keeps the item text beside the slots of Blizzard's Forever sheet
-- (CludesUIBlizzardSkin_CharacterSheetForever.lua). The card's Off stops
-- all of it (the callers' enable-key gates).
function mod.CharSheetStyle()
    local v = mod._csStyle
    if v == nil then
        if not CludesUIDB then
            return "cui"
        end
        local styles = CludesUIDB.blizzWindowSkinStyles
        v = (type(styles) == "table" and styles.charsheet == "blizzard") and "blizzard" or "cui"
        mod._csStyle = v
    end
    return v
end
function mod.CharSheetStock()
    return mod.CharSheetStyle() ~= "cui"
end
-- Blizz Default on WoW Forever: the slot text on Blizzard's Forever sheet.
-- False off Forever.
function mod.CharSheetForever()
    return CludesUI.IS_FOREVER == true and mod.CharSheetStock()
end
-- Stock styles' "Blizzard UI Color" (on unless turned off): every stat
-- category in Blizzard's yellow in place of its own colour. nil when it does
-- not apply (always under the CludesUI look).
-- Stock styles: Blizzard's stats pane parked off-screen (method calls, never
-- Hide) so the CludesUI stats section, a child of the pane anchored over
-- its InsetRight slot, replaces its list while the pane's own Show/Hide
-- keeps driving visibility. Idempotent (compare-gated on the parked point).
function mod.CharSheetParkStatsPane()
    local panel, castFrame = _G.CharacterStatsPane, _G.CharacterFrame
    if not (panel and castFrame) then
        return
    end
    if panel:GetNumPoints() == 1 then
        local _, rel, _, _, posY = panel:GetPoint(1)
        if rel == castFrame and posY == -10000 then
            return
        end
    end
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", castFrame, "BOTTOMLEFT", 0, -10000)
end
function mod.CharSheetBlizzColor()
    if not mod.CharSheetStock() then
        return nil
    end
    if CludesUIDB and CludesUIDB.charSheetBlizzColors == false then
        return nil
    end
    local c = mod._csBlizzYellow
    if not c then
        local num = _G.NORMAL_FONT_COLOR
        c = { r = num and num.r or 1, g = num and num.g or 0.82, b = num and num.b or 0 }
        mod._csBlizzYellow = c
    end
    return c
end

-- Same reading as the Chat sidebar icon and the DataBars block: the LOWEST
-- percent across equipped slots 1-18 (the weakest item), floored.
local function GetDurabilityPercent()
    local lowest = 100
    for slotId = 1, 18 do
        local current, mx = GetInventoryItemDurability(slotId)
        if current and mx and mx > 0 then
            local percent = current / mx * 100
            if percent < lowest then
                lowest = percent
            end
        end
    end
    return math.floor(lowest)
end

local function GetDurabilityTextColor(percent)
    if percent > 50 then
        return (100 - percent) / 50, 1, 0
    end
    return 1, percent / 50, 0
end

local function FormatDurabilityText(percent, showLabel)
    if showLabel then
        return L("Durability") .. ": " .. percent .. "%"
    end
    return percent .. "%"
end

-- "gear" = the 16 slots with ilvl/enchants/sockets.
-- "all"  = gear + shirt + tabard (cosmetic), for full-character loops.
local CUI_GEAR_SLOTS = {
    "CharacterHeadSlot",
    "CharacterNeckSlot",
    "CharacterShoulderSlot",
    "CharacterBackSlot",
    "CharacterChestSlot",
    "CharacterWaistSlot",
    "CharacterLegsSlot",
    "CharacterFeetSlot",
    "CharacterWristSlot",
    "CharacterHandsSlot",
    "CharacterFinger0Slot",
    "CharacterFinger1Slot",
    "CharacterTrinket0Slot",
    "CharacterTrinket1Slot",
    "CharacterMainHandSlot",
    "CharacterSecondaryHandSlot",
}
local CUI_ALL_SLOTS = {
    "CharacterHeadSlot",
    "CharacterNeckSlot",
    "CharacterShoulderSlot",
    "CharacterBackSlot",
    "CharacterChestSlot",
    "CharacterShirtSlot",
    "CharacterTabardSlot",
    "CharacterWristSlot",
    "CharacterHandsSlot",
    "CharacterWaistSlot",
    "CharacterLegsSlot",
    "CharacterFeetSlot",
    "CharacterTrinket0Slot",
    "CharacterTrinket1Slot",
    "CharacterFinger0Slot",
    "CharacterFinger1Slot",
    "CharacterMainHandSlot",
    "CharacterSecondaryHandSlot",
}

-- Prefer EquipmentManager_EquipSet over raw C_EquipmentSet (cleaner from insecure code). Callers must combat-guard.
local function CUI_EquipSet(setID)
    if not setID then
        return
    end
    if EquipmentManager_EquipSet then
        EquipmentManager_EquipSet(setID)
    else
        C_EquipmentSet.UseEquipmentSet(setID)
    end
end

-- C_TooltipInfo scanning. NEVER create a scanning GameTooltipTemplate from Lua (CLAUDE.md reference_tooltip_template_taint).
local function CUI_ScanInventoryItem(slotID, unitToken)
    if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem) then
        return nil
    end
    local payload = C_TooltipInfo.GetInventoryItem(unitToken or "player", slotID)
    if not payload then
        return nil
    end
    if TooltipUtil and TooltipUtil.SurfaceArgs then
        TooltipUtil.SurfaceArgs(payload)
    end
    return payload
end

-- Upgrade track lookup lives in CludesUI.lua so Bags shares it; hot-path alias.
local CUI_GetUpgradeTrack = CludesUI.GetUpgradeTrack

-- Language-agnostic: line-type match (Enum.TooltipDataLineType.ItemEnchantmentPermanent / 15)
-- first, else a pattern from the localized ENCHANTED_TOOLTIP_LINE. Cached by enchantID per session.
local _enchantNameCache = {}
local _ENCHANT_LINE_TYPE = (
    Enum
    and Enum.TooltipDataLineType
    and (Enum.TooltipDataLineType.ItemEnchantmentPermanent or Enum.TooltipDataLineType.ItemEnchant)
) or 15

-- Pattern from ENCHANTED_TOOLTIP_LINE: escape magic chars, %s becomes the capture.
local _ENCHANT_PATTERN
do
    local formatStr = ENCHANTED_TOOLTIP_LINE
    if formatStr then
        local head, tail = formatStr:match("^(.-)%%s(.*)$")
        if head then
            local function esc(s)
                return (s:gsub("([%(%)%.%[%]%^%$%*%+%-%?%%])", "%%%1"))
            end
            _ENCHANT_PATTERN = "^" .. esc(head) .. "(.+)" .. esc(tail) .. "$"
        end
    end
end

local function _stripLineEscapes(s)
    if not s then
        return ""
    end
    -- Keep |A:...|a atlas escapes (renderer shows the icon, hides the text); strip only colors + leading +/&.
    s = s:gsub("|cn.-:(.-)|r", "%1") -- new-style color escapes
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "") -- classic color open
    s = s:gsub("|r", "") -- color close
    s = s:gsub("^%s*[%+&]%s*", "") -- leading + or &
    return s
end

local function CUI_GetEnchantText(slotID, unitToken)
    if not slotID then
        return ""
    end
    local link = GetInventoryItemLink(unitToken or "player", slotID)
    if not link then
        return ""
    end

    -- Item link format: "item:<itemID>:<enchantID>:..."
    local enchantID = tonumber(link:match("item:%d+:(%d+)"))
    if not enchantID or enchantID == 0 then
        return ""
    end

    local cached = _enchantNameCache[enchantID]
    if cached ~= nil then
        return cached
    end

    local payload = CUI_ScanInventoryItem(slotID, unitToken)
    if not (payload and payload.lines) then
        return ""
    end

    for _, line in ipairs(payload.lines) do
        local raw = _stripLineEscapes(line.leftText or "")
        local matched
        if line.type == _ENCHANT_LINE_TYPE then
            matched = raw
        elseif _ENCHANT_PATTERN then
            matched = raw:match(_ENCHANT_PATTERN)
        else
            matched = raw:match("^Enchanted:%s*(.+)$")
        end
        if matched and matched ~= "" then
            matched = matched:gsub("^Enchant%s+[^-]+%s*-%s*", "")
            _enchantNameCache[enchantID] = matched
            return matched
        end
    end

    -- Deliberately not cached. A scan can come back empty because the item's data has
    -- not arrived yet, and the sheet already re-reads on GET_ITEM_INFO_RECEIVED for
    -- exactly that -- caching the empty answer made the miss permanent and threw that
    -- refresh away, leaving an enchanted item flagged as missing for the session.
    return ""
end

CludesUI.GetEnchantText = CUI_GetEnchantText

-- Shared with the inspect sheet (loads after this file) through ns.
-- Slots that can have enchants in current expansion.
local ENCHANT_SLOTS = {
    [INVSLOT_HEAD] = true,
    [INVSLOT_SHOULDER] = true,
    [INVSLOT_BACK] = false,
    [INVSLOT_CHEST] = true,
    [INVSLOT_WRIST] = false,
    [INVSLOT_LEGS] = true,
    [INVSLOT_FEET] = true,
    [INVSLOT_FINGER1] = true,
    [INVSLOT_FINGER2] = true,
    [INVSLOT_MAINHAND] = true,
    -- INVSLOT_OFFHAND deliberately absent: whether it can be enchanted depends on
    -- what's equipped there (weapon vs. shield/held item), checked dynamically below.
}

-- Enchant label parts for one slot: iconOnly keeps the |A:...|a atlas escapes
-- (red icon when missing), tooltipText is the readable name. Only flags
-- missing enchants at level 90+: leveling gear churn would fire it constantly.
function mod.ParseEnchantLabel(enchantText, slotID, linkText, unitToken)
    local canHaveEnchant = ENCHANT_SLOTS[slotID]
    if slotID == INVSLOT_OFFHAND and linkText then
        local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(linkText)
        canHaveEnchant = (classID == Enum.ItemClass.Weapon)
    end
    local lvl = UnitLevel(unitToken)
    local atEnchantLevel = lvl and not (issecretvalue and issecretvalue(lvl)) and lvl >= 90 or false
    local isMissing = atEnchantLevel
        and canHaveEnchant
        and linkText
        and (enchantText == "" or not enchantText)
    local hasEnchant = enchantText and enchantText ~= ""

    local iconOnly, tooltipText
    if isMissing then
        -- Same hex atlas enchanted items show, tinted red (#e54949 =
        -- 229, 73, 73 in the atlas-escape color fields).
        iconOnly = "|A:Professions-ChatIcon-Quality-Tier5:14:14:0:0:229:73:73|a"
        tooltipText = "Enchant missing"
    elseif hasEnchant then
        -- Concatenate every |A:...|a atlas escape, drop everything else.
        local icons = {}
        for atlas in enchantText:gmatch("|A:[^|]+|a") do
            icons[#icons + 1] = atlas
        end
        iconOnly = table.concat(icons, "")
        tooltipText = enchantText:gsub("|A:[^|]+|a", ""):gsub("^%s+", ""):gsub("%s+$", "")
        -- Strip any "prefix - " (e.g. "Enchant Weapon - ") so the tooltip
        -- shows just the enchant's readable name.
        tooltipText = tooltipText:gsub("^.-%s*%-%s*", "")
    end
    return iconOnly, tooltipText, isMissing, hasEnchant
end

-- Mythic+ score color: highest threshold that the score meets wins.
local MP_COLOR_BRACKETS = {
    { 3850, "ff8000" },
    { 3695, "f9753f" },
    { 3575, "f16961" },
    { 3455, "e75e7f" },
    { 3335, "db529c" },
    { 3215, "cc47b9" },
    { 3095, "b83dd6" },
    { 2965, "9c3eed" },
    { 2845, "715be5" },
    { 2725, "2c6dde" },
    { 2565, "3b7fcd" },
    { 2445, "5292b9" },
    { 2325, "5ca6a4" },
    { 2205, "5fba8d" },
    { 2085, "5cce75" },
    { 1965, "50e258" },
    { 1845, "35f72d" },
    { 1725, "3eff26" },
    { 1600, "5eff43" },
    { 1475, "74ff58" },
    { 1350, "88ff6b" },
    { 1225, "98ff7d" },
    { 1100, "a8ff8d" },
    { 975, "b6ff9e" },
    { 850, "c3ffae" },
    { 725, "cfffbd" },
    { 600, "dbffcd" },
    { 475, "e7ffdd" },
    { 350, "f2ffec" },
    { 225, "fdfffc" },
    { 200, "ffffff" },
}
function mod.GetMPScoreHex(score)
    for i = 1, #MP_COLOR_BRACKETS do
        if score >= MP_COLOR_BRACKETS[i][1] then
            return MP_COLOR_BRACKETS[i][2]
        end
    end
    return "ffffff"
end

-- Sheet backdrop: modern_blizz atlas + 0.62 black overlay. The atlas covers the
-- frame without distorting: native aspect 561x433, and on resize the tex coords
-- are recomputed centered, cropping the overflow. Returns bg, overlay.
function mod.SheetBackdrop(widget)
    local BG_ASPECT = 561 / 433
    local backdrop = widget:CreateTexture(nil, "BACKGROUND", nil, -8)
    backdrop:SetTexture("Interface\\AddOns\\CludesUI\\media\\modern_blizz.png")
    backdrop:SetAllPoints(widget)
    backdrop:SetAlpha(1)
    local overlayFrame = widget:CreateTexture(nil, "BACKGROUND", nil, -7)
    overlayFrame:SetColorTexture(0, 0, 0, 0.62)
    overlayFrame:SetAllPoints(widget)

    local BASE_L, BASE_R, BASE_T, BASE_B = 0.25, 1, 0, 0.75
    local BASE_U = BASE_R - BASE_L -- 0.75
    local BASE_V = BASE_B - BASE_T -- 0.75
    local function UpdateBgTexCoords()
        local fw, fh = widget:GetSize()
        -- Secrecy test BEFORE the zero check: that check is itself a
        -- comparison and throws on a secret size. Matches the engine.
        if issecretvalue and (issecretvalue(fw) or issecretvalue(fh)) then
            return
        end
        if fw == 0 or fh == 0 then
            return
        end
        local frameAspect = fw / fh
        if frameAspect > BG_ASPECT then
            local visV = BASE_V * (BG_ASPECT / frameAspect)
            local trimV = (BASE_V - visV) / 2
            backdrop:SetTexCoord(BASE_L, BASE_R, BASE_T + trimV, BASE_B - trimV)
        else
            local visU = BASE_U * (frameAspect / BG_ASPECT)
            local trimU = (BASE_U - visU) / 2
            backdrop:SetTexCoord(BASE_L + trimU, BASE_R - trimU, BASE_T, BASE_B)
        end
    end
    -- One script hook instead of three setter hooks; also fires for
    -- anchor-driven resizes (same shape as WSkin.Shell).
    widget:HookScript("OnSizeChanged", UpdateBgTexCoords)
    UpdateBgTexCoords()
    return backdrop, overlayFrame
end

-- Empty-socket atlas map (key names come from GetItemStats return keys).
local CUI_EMPTY_SOCKET_ATLAS = {
    EMPTY_SOCKET_META = "socket-meta",
    EMPTY_SOCKET_RED = "socket-red",
    EMPTY_SOCKET_YELLOW = "socket-yellow",
    EMPTY_SOCKET_BLUE = "socket-blue",
    EMPTY_SOCKET_HYDRAULIC = "socket-hydraulic",
    EMPTY_SOCKET_COGWHEEL = "socket-cogwheel",
    EMPTY_SOCKET_PRISMATIC = "socket-prismatic",
    EMPTY_SOCKET_PUNCHCARDRED = "socket-punchcardred",
    EMPTY_SOCKET_PUNCHCARDYELLOW = "socket-punchcardyellow",
    EMPTY_SOCKET_PUNCHCARDBLUE = "socket-punchcardblue",
    EMPTY_SOCKET_DOMINATION = "socket-domination",
    EMPTY_SOCKET_CYPHER = "socket-cypher",
    EMPTY_SOCKET_PRIMORDIAL = "socket-primordial",
    EMPTY_SOCKET_TINKER = "socket-tinker",
}

-- Gem socket icons: one pass over GetItemStats + C_Item.GetItemGem (no tooltip). paintPasses
-- (the slot's cuiGemPaintPasses) suppresses empty-socket atlas rows for the first frames after
-- /reload while gem bytes hydrate.
local function CUI_BuildSocketIconRow(linkText, paintPasses)
    local row = {}
    local gemLinks = {}
    if not linkText or not C_Item or not C_Item.GetItemGem or not C_Item.GetItemStats then
        return row, 0, 0, gemLinks
    end

    local stats = C_Item.GetItemStats(linkText)
    local totalSockets = 0
    local firstAtlas
    if stats then
        for key, total in pairs(stats) do
            local atlas = CUI_EMPTY_SOCKET_ATLAS[key]
            if atlas and total and total > 0 then
                totalSockets = totalSockets + total
                firstAtlas = firstAtlas or atlas
            end
        end
    end

    for i = 1, 4 do
        local _, gemLink = C_Item.GetItemGem(linkText, i)
        if gemLink then
            gemLinks[#gemLinks + 1] = gemLink
            local iconTex = C_Item.GetItemIconByID(gemLink)
            if not iconTex then
                iconTex = select(5, C_Item.GetItemInfoInstant(gemLink))
            end
            row[#row + 1] = { icon = iconTex or 134400, isAtlas = false }
        end
    end
    local nGems = #gemLinks

    -- EMPTY_SOCKET_* counts total sockets; subtract filled for empty atlas rows.
    local suppressEmptyAtlas = (totalSockets > 0 and nGems == 0 and (paintPasses or 0) < 40)
    if stats and not suppressEmptyAtlas and firstAtlas then
        local emptyCount = math.max(0, totalSockets - nGems)
        if emptyCount > 0 then
            for _ = 1, emptyCount do
                row[#row + 1] = { icon = firstAtlas, isAtlas = true }
            end
        end
    end

    return row, totalSockets, nGems, gemLinks
end

-- Default the themed sheet + its sub-displays on first install. Keys are stamped
-- only when nil, so a user who explicitly turned something off keeps that choice.
do
    local defaultStamp = CreateFrame("Frame")
    defaultStamp:RegisterEvent("ADDON_LOADED")
    defaultStamp:SetScript("OnEvent", function(self, _, addon)
        if addon ~= "CludesUI" then
            return
        end
        self:UnregisterAllEvents()
        if not CludesUIDB then
            CludesUIDB = {}
        end
        local defaultSet = {
            themedCharacterSheet = true,
            showMythicRating = false,
            showItemLevel = true,
            showUpgradeTrack = true,
            showEnchants = true,
            showGems = true,
            showStatCategory_Attributes = true,
            showStatCategory_Attack = true,
            showStatCategory_Defense = true,
            showStatCategory_SecondaryStats = true,
            showStatCategory_Tertiary = true,
            showStatCategory_Crests = true,
            showStatCategory_PvP = true,
            showAdjustedStats = false,
            showManaStat = false,
            showCharSheetDurability = false,
            charSheetSeasonPanel = true,
            charSheetHideSlotFlyoutArrows = false,
            charSheetDurabilityLocation = "model",
            charSheetDurabilityShowLabel = true,
            highlightSecondaryItems = false,
            highlightTertiaryItems = false,
        }
        for keyName, v in pairs(defaultSet) do
            if CludesUIDB[keyName] == nil then
                CludesUIDB[keyName] = v
            end
        end
    end)
end

-- Lightweight pre-skin: chrome hides, bg, inset. Safe while CharacterFrame is hidden (before first open); running it mid-OnShow blocks the Rep/Currency ScrollBox data render.
local _preSkinned = false
local function PreSkinCharacterSheet()
    if _preSkinned then
        return
    end
    _preSkinned = true

    local widget = CharacterFrame
    if not widget then
        _preSkinned = false
        return
    end

    if CharacterFrame.NineSlice then
        CharacterFrame.NineSlice:Hide()
    end
    if widget.Background then
        widget.Background:Hide()
    end
    if widget.TitleBg then
        widget.TitleBg:Hide()
    end
    if widget.TopTileStreaks then
        widget.TopTileStreaks:Hide()
    end
    if widget.Portrait then
        widget.Portrait:Hide()
    end
    if CharacterFramePortrait then
        CharacterFramePortrait:Hide()
    end
    if CharacterModelFrameBackgroundOverlay then
        CharacterModelFrameBackgroundOverlay:Hide()
    end
    if CharacterModelFrameBackgroundTopLeft then
        CharacterModelFrameBackgroundTopLeft:Hide()
    end
    if CharacterModelFrameBackgroundBotLeft then
        CharacterModelFrameBackgroundBotLeft:Hide()
    end
    if CharacterModelFrameBackgroundTopRight then
        CharacterModelFrameBackgroundTopRight:Hide()
    end
    if CharacterModelFrameBackgroundBotRight then
        CharacterModelFrameBackgroundBotRight:Hide()
    end
    if CharacterFrameInsetRight then
        if CharacterFrameInsetRight.NineSlice then
            CharacterFrameInsetRight.NineSlice:Hide()
        end
        CharacterFrameInsetRight:ClearAllPoints()
        CharacterFrameInsetRight:SetPoint("TOPLEFT", widget, "TOPLEFT", 10000, -10000)
    end
    if CharacterFrameInsetBG then
        CharacterFrameInsetBG:Hide()
    end
    if CharacterFrameInset and CharacterFrameInset.NineSlice then
        for _, edge in ipairs({
            "TopEdge",
            "BottomEdge",
            "LeftEdge",
            "RightEdge",
            "TopLeftCorner",
            "TopRightCorner",
            "BottomLeftCorner",
            "BottomRightCorner",
        }) do
            if CharacterFrameInset.NineSlice[edge] then
                CharacterFrameInset.NineSlice[edge]:Hide()
            end
        end
        CharacterFrameInset.NineSlice:SetAlpha(0)
    end
    local FRAME_BG_R, FRAME_BG_G, FRAME_BG_B = 0.03, 0.045, 0.05
    if CharacterFrameInset then
        if CharacterFrameInset.AbsBg then
            CharacterFrameInset.AbsBg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B, 1)
        end
        if CharacterFrameInset.Bg then
            CharacterFrameInset.Bg:SetColorTexture(0.02, 0.02, 0.025, 1)
            CharacterFrameInset.Bg:SetAlpha(0)
        end
    end
    if CharacterModelScene then
        CharacterModelScene:SetAlpha(0)
        CharacterModelScene:EnableMouse(false)
        if CharacterModelScene.EnableMouseWheel then
            CharacterModelScene:EnableMouseWheel(false)
        end
        if CharacterModelScene.ControlFrame then
            CharacterModelScene.ControlFrame:SetAlpha(0)
            CharacterModelScene.ControlFrame:EnableMouse(false)
        end
    end
    local regionList = { widget:GetRegions() }
    for i = 1, #regionList do
        local regionFrame = regionList[i]
        if regionFrame and regionFrame:IsObjectType("Texture") then
            regionFrame:SetAlpha(0)
        end
    end
    local backdrop, bgOverlay = mod.SheetBackdrop(widget)
    GetFFD(widget).bg = backdrop
    GetFFD(widget).bgOverlay = bgOverlay
    -- Standard window-reskin border (AdventureMap_TopBorder atlas), as on every skinned window.
    if mod.WSkin and mod.WSkin.AtlasBorder then
        mod.WSkin.AtlasBorder(widget)
    end
    -- Lets the Modern flat backdrop live-swap in for the atlas when the user picks Modern here.
    if mod.WSkin and mod.WSkin.AdoptShell then
        mod.WSkin.AdoptShell("charsheet", widget, backdrop, GetFFD(widget).bgOverlay)
    end

    -- PlayerModel: SetUnit("player") natively follows shapeshift forms and Dracthyr Visage. Backdrop + hover glow live on a sibling frame (the 3D model draws on top).
    -- Its level (and the text overlays' after it) comes from CharacterFrame's own, never a fixed
    -- number: the sheet backdrop is that frame's BACKGROUND layer, its inset shares the level, and
    -- the window's level at login varies. Children keep the offset when the window is raised.
    if not GetFFD(widget).modelScene then
        local modelFrame = CreateFrame("PlayerModel", "CUI_CharSheet_ModelScene", widget)
        modelFrame:SetFrameLevel(widget:GetFrameLevel() + 3)
        if CharacterHeadSlot then
            modelFrame:SetPoint("TOPLEFT", CharacterHeadSlot, "TOPRIGHT", 0, 0)
        end
        if CharacterHandsSlot then
            modelFrame:SetPoint("TOPRIGHT", CharacterHandsSlot, "TOPLEFT", 0, 0)
        end
        if CharacterMainHandSlot then
            modelFrame:SetPoint("BOTTOM", CharacterMainHandSlot, "TOP", 0, 0)
        else
            modelFrame:SetPoint("BOTTOM", widget, "BOTTOM", 0, 60)
        end
        modelFrame:EnableMouse(true)
        modelFrame:EnableMouseWheel(true)

        -- Custom model background (our frame, no taint risk)
        local bgFrame = CreateFrame("Frame", nil, widget)
        bgFrame:SetFrameLevel(math.max(1, modelFrame:GetFrameLevel() - 1))
        bgFrame:SetPoint("TOPLEFT", CharacterHeadSlot, "TOPLEFT", -8, 10)
        bgFrame:SetPoint("BOTTOMRIGHT", modelFrame, "BOTTOMRIGHT", 0, -18)
        local bgTex = bgFrame:CreateTexture(nil, "BACKGROUND")
        bgTex:SetAllPoints(bgFrame)
        bgTex:SetTexture("Interface\\AddOns\\CludesUIBlizzardSkin\\Media\\character-bg.png")
        bgTex:SetAlpha(1)

        GetFFD(widget).modelBg = bgTex
        GetFFD(widget).modelBgFrame = bgFrame

        modelFrame:SetUnit("player")
        local zoomLevel = 0 -- 0 = full body, 1 = tight portrait
        modelFrame:SetPortraitZoom(zoomLevel)

        GetFFD(widget).modelScene = modelFrame -- key name kept for older refs
        GetFFD(widget).modelActor = modelFrame

        -- LMB drag rotates, RMB drag pans, wheel zooms.
        local ROTATE_SPEED = 0.012
        local PAN_SPEED = 0.01
        local ZOOM_STEP = 0.1

        local mouseOverlay = CreateFrame("Frame", nil, modelFrame)
        mouseOverlay:SetAllPoints(modelFrame)
        mouseOverlay:SetFrameLevel(modelFrame:GetFrameLevel() + 5)
        mouseOverlay:EnableMouse(true)
        mouseOverlay:EnableMouseWheel(true)
        mouseOverlay:RegisterForDrag("LeftButton", "RightButton")

        local dragMode
        local lastX, lastY

        local function _dragOnUpdate(self)
            if not dragMode then
                self:SetScript("OnUpdate", nil)
                return
            end
            if dragMode == "rotate" and not IsMouseButtonDown("LeftButton") then
                dragMode = nil
                self:SetScript("OnUpdate", nil)
                return
            elseif dragMode == "pan" and not IsMouseButtonDown("RightButton") then
                dragMode = nil
                self:SetScript("OnUpdate", nil)
                return
            end

            local cx, cy = GetCursorPosition()
            local scale = self:GetEffectiveScale()
            local posX, posY = cx / scale, cy / scale
            local dx, dy = posX - lastX, posY - lastY
            lastX, lastY = posX, posY

            if dragMode == "rotate" then
                modelFrame:SetFacing((modelFrame:GetFacing() or 0) + dx * ROTATE_SPEED)
            elseif dragMode == "pan" then
                -- Model:SetPosition(forward, side, up); depth is fixed, so panning slides in screen space only.
                if modelFrame.GetPosition and modelFrame.SetPosition then
                    local pixel, py, pz = modelFrame:GetPosition()
                    modelFrame:SetPosition(pixel or 0, (py or 0) + dx * PAN_SPEED, (pz or 0) + dy * PAN_SPEED)
                end
            end
        end

        mouseOverlay:SetScript("OnMouseDown", function(self, btnFrame)
            local cx, cy = GetCursorPosition()
            local scale = self:GetEffectiveScale()
            lastX, lastY = cx / scale, cy / scale
            if btnFrame == "LeftButton" then
                dragMode = "rotate"
            elseif btnFrame == "RightButton" then
                dragMode = "pan"
            end
            self:SetScript("OnUpdate", _dragOnUpdate)
        end)
        mouseOverlay:SetScript("OnMouseUp", function(self)
            dragMode = nil
            self:SetScript("OnUpdate", nil)
        end)
        mouseOverlay:SetScript("OnHide", function(self)
            dragMode = nil
            self:SetScript("OnUpdate", nil)
        end)

        -- SetUnit loads asynchronously and the widget drops its camera while hidden; recentre once the model is in.
        modelFrame:SetScript("OnModelLoaded", function(self)
            self:RefreshCamera()
            self:SetPortraitZoom(zoomLevel)
            self:SetPosition(0, 0, 0)
        end)

        mouseOverlay:SetScript("OnMouseWheel", function(_, delta)
            zoomLevel = math.max(0, math.min(1, zoomLevel + delta * ZOOM_STEP))
            modelFrame:SetPortraitZoom(zoomLevel)
        end)

        -- SetUnit handles form transitions; re-bind on equipment change so new gear shows.
        local function _refreshPlayerModel()
            if GetFFD(widget).modelScene and GetFFD(widget).modelScene.SetUnit then
                GetFFD(widget).modelScene:SetUnit("player")
            end
        end
        GetFFD(widget).refreshPlayerModel = _refreshPlayerModel

        local refresh = CreateFrame("Frame")
        refresh:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        refresh:RegisterEvent("TRANSMOGRIFY_UPDATE")
        refresh:RegisterEvent("UNIT_MODEL_CHANGED")
        refresh:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
        refresh:RegisterEvent("PLAYER_ENTERING_WORLD")
        refresh:SetScript("OnEvent", function(_, evt, unitToken)
            -- SetUnit forces a full 3D model reload and UPDATE_SHAPESHIFT_FORM storms in combat, so only pay it while visible; the OnShow hook below re-binds, so closed changes land.
            if not (widget and widget:IsShown()) then
                return
            end
            if evt == "UNIT_MODEL_CHANGED" and unitToken and unitToken ~= "player" then
                return
            end
            _refreshPlayerModel()
        end)

        if widget.HookScript then
            widget:HookScript("OnShow", function()
                if GetFFD(widget).refreshPlayerModel then
                    GetFFD(widget).refreshPlayerModel()
                end
            end)
        end
    end

    if CharacterFrameTitleText then
        CharacterFrameTitleText:ClearAllPoints()
        CharacterFrameTitleText:SetPoint("TOP", widget, "TOP", 0, -6)
        CharacterFrameTitleText:SetJustifyH("CENTER")
    end
    if CharacterLevelText and CharacterFrameTitleText then
        CharacterLevelText:ClearAllPoints()
        CharacterLevelText:SetPoint("TOP", CharacterFrameTitleText, "BOTTOM", 0, -5)
        CharacterLevelText:SetJustifyH("CENTER")
    end

    if CharacterModelFrameHelpText then
        CharacterModelFrameHelpText:Hide()
    end

    if CharacterFrameInsetBG then
        CharacterFrameInsetBG:Hide()
    end
    if CharacterFrameInset and CharacterFrameInset.NineSlice then
        for _, edge in ipairs({
            "TopEdge",
            "BottomEdge",
            "LeftEdge",
            "RightEdge",
            "TopLeftCorner",
            "TopRightCorner",
            "BottomLeftCorner",
            "BottomRightCorner",
        }) do
            if CharacterFrameInset.NineSlice[edge] then
                CharacterFrameInset.NineSlice[edge]:Hide()
            end
        end
        CharacterFrameInset.NineSlice:SetAlpha(0)
    end
    if CharacterFrameInset and CharacterFrameInset.Bg then
        CharacterFrameInset.Bg:SetAlpha(0)
    end

    if widget.PaperDollFrame then
        if widget.PaperDollFrame.InnerBorder then
            for _, name in ipairs({
                "Top",
                "Bottom",
                "Left",
                "Right",
                "TopLeft",
                "TopRight",
                "BottomLeft",
                "BottomRight",
            }) do
                if widget.PaperDollFrame.InnerBorder[name] then
                    widget.PaperDollFrame.InnerBorder[name]:Hide()
                end
            end
        end
    end

    for _, name in ipairs({
        "TopLeft",
        "TopRight",
        "BottomLeft",
        "BottomRight",
        "Top",
        "Bottom",
        "Left",
        "Right",
        "Bottom2",
    }) do
        if _G["PaperDollInnerBorder" .. name] then
            _G["PaperDollInnerBorder" .. name]:Hide()
        end
    end

    if PaperDollItemsFrame then
        PaperDollItemsFrame:Hide()
    end

    if _G["CharacterSecondaryHandSlot.26129b81ae0"] then
        _G["CharacterSecondaryHandSlot.26129b81ae0"]:Hide()
    end

    -- Hide the SlotFrame wrappers -- we reposition the inner slot buttons directly.
    if _G.CharacterBackSlotFrame then
        _G.CharacterBackSlotFrame:Hide()
    end
    if _G.CharacterChestSlotFrame then
        _G.CharacterChestSlotFrame:Hide()
    end
    if _G.CharacterFeetSlotFrame then
        _G.CharacterFeetSlotFrame:Hide()
    end
    if _G.CharacterFinger0SlotFrame then
        _G.CharacterFinger0SlotFrame:Hide()
    end
    if _G.CharacterFinger1SlotFrame then
        _G.CharacterFinger1SlotFrame:Hide()
    end
    if _G.CharacterHandsSlotFrame then
        _G.CharacterHandsSlotFrame:Hide()
    end
    if _G.CharacterHeadSlotFrame then
        _G.CharacterHeadSlotFrame:Hide()
    end
    if _G.CharacterLegsSlotFrame then
        _G.CharacterLegsSlotFrame:Hide()
    end
    if _G.CharacterMainHandSlotFrame then
        _G.CharacterMainHandSlotFrame:Hide()
    end
    if _G.CharacterNeckSlotFrame then
        _G.CharacterNeckSlotFrame:Hide()
    end
    if _G.CharacterSecondaryHandSlotFrame then
        _G.CharacterSecondaryHandSlotFrame:Hide()
    end
    if _G.CharacterShirtSlotFrame then
        _G.CharacterShirtSlotFrame:Hide()
    end
    if _G.CharacterShoulderSlotFrame then
        _G.CharacterShoulderSlotFrame:Hide()
    end
    if _G.CharacterTabardSlotFrame then
        _G.CharacterTabardSlotFrame:Hide()
    end
    if _G.CharacterTrinket0SlotFrame then
        _G.CharacterTrinket0SlotFrame:Hide()
    end
    if _G.CharacterTrinket1SlotFrame then
        _G.CharacterTrinket1SlotFrame:Hide()
    end
    if _G.CharacterWaistSlotFrame then
        _G.CharacterWaistSlotFrame:Hide()
    end
    if _G.CharacterWristSlotFrame then
        _G.CharacterWristSlotFrame:Hide()
    end

    -- Grid layout via SetPoint only. Never reparent -- slots are secure and reparenting would taint the paper-doll.
    if CharacterFrameBg then
        CharacterFrameBg:Show()
    end

    local slotNames = {
        "CharacterHeadSlot",
        "CharacterNeckSlot",
        "CharacterShoulderSlot",
        "CharacterBackSlot",
        "CharacterChestSlot",
        "CharacterShirtSlot",
        "CharacterTabardSlot",
        "CharacterWristSlot",
        "CharacterHandsSlot",
        "CharacterWaistSlot",
        "CharacterLegsSlot",
        "CharacterFeetSlot",
        "CharacterTrinket0Slot",
        "CharacterTrinket1Slot",
        "CharacterFinger0Slot",
        "CharacterFinger1Slot",
        "CharacterMainHandSlot",
        "CharacterSecondaryHandSlot",
    }

    for _, slotKey in ipairs(slotNames) do
        local slotFrame = _G[slotKey]
        if slotFrame then
            slotFrame:Show()
            local hostFrame = slotFrame:GetParent()
            if hostFrame then
                hostFrame:Show()
            end
        end
    end

    local gridCols = 2
    local cellWidth = 280
    local cellHeight = 41
    local gridStartX = 14
    local gridStartY = -60

    local slotGridMap = {
        CharacterHeadSlot = { col = 0, row = 0 },
        CharacterNeckSlot = { col = 0, row = 1 },
        CharacterShoulderSlot = { col = 0, row = 2 },
        CharacterBackSlot = { col = 0, row = 3 },
        CharacterChestSlot = { col = 0, row = 4 },
        CharacterShirtSlot = { col = 0, row = 5 },
        CharacterTabardSlot = { col = 0, row = 6 },
        CharacterWristSlot = { col = 0, row = 7 },
        CharacterHandsSlot = { col = 1, row = 0 },
        CharacterWaistSlot = { col = 1, row = 1 },
        CharacterLegsSlot = { col = 1, row = 2 },
        CharacterFeetSlot = { col = 1, row = 3 },
        CharacterFinger0Slot = { col = 1, row = 4 },
        CharacterFinger1Slot = { col = 1, row = 5 },
        CharacterTrinket0Slot = { col = 1, row = 6 },
        CharacterTrinket1Slot = { col = 1, row = 7 },
    }

    for slotKey, gridPos in pairs(slotGridMap) do
        local slotFrame = _G[slotKey]
        if slotFrame then
            slotFrame:ClearAllPoints()
            local xOffset = gridStartX + (gridPos.col * cellWidth)
            local offY = gridStartY - (gridPos.row * cellHeight)
            slotFrame:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", xOffset, offY)
        end
    end

    -- Weapons live in the bottom strip, outside the 2-column grid.
    _G.CharacterMainHandSlot:ClearAllPoints()
    _G.CharacterMainHandSlot:SetPoint("BOTTOMLEFT", CharacterFrame, "BOTTOMLEFT", 128, 10)
    _G.CharacterSecondaryHandSlot:ClearAllPoints()
    _G.CharacterSecondaryHandSlot:SetPoint("TOPLEFT", _G.CharacterMainHandSlot, "TOPRIGHT", 12, 0)

    -- Weapon-slot regions 16/17 are the ornamented border/frame textures. Shifting texcoords off-atlas is cheaper than SetTexture("") and survives Blizzard re-applying the atlas.
    do
        local region = select(16, _G.CharacterMainHandSlot:GetRegions())
        if region then
            region:SetTexCoord(0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
        end
    end
    do
        local region = select(17, _G.CharacterMainHandSlot:GetRegions())
        if region then
            region:SetTexCoord(0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
        end
    end
    do
        local region = select(16, _G.CharacterSecondaryHandSlot:GetRegions())
        if region then
            region:SetTexCoord(0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
        end
    end
    do
        local region = select(17, _G.CharacterSecondaryHandSlot:GetRegions())
        if region then
            region:SetTexCoord(0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
        end
    end

    -- Strip icon borders and crop icon texcoords so icons fill the slot cleanly.
    local slotsToHide = {
        "CharacterBackSlot",
        "CharacterChestSlot",
        "CharacterFeetSlot",
        "CharacterFinger0Slot",
        "CharacterFinger1Slot",
        "CharacterHandsSlot",
        "CharacterHeadSlot",
        "CharacterLegsSlot",
        "CharacterMainHandSlot",
        "CharacterNeckSlot",
        "CharacterSecondaryHandSlot",
        "CharacterShirtSlot",
        "CharacterShoulderSlot",
        "CharacterTabardSlot",
        "CharacterTrinket0Slot",
        "CharacterTrinket1Slot",
        "CharacterWaistSlot",
        "CharacterWristSlot",
    }

    for _, slotKey in ipairs(slotsToHide) do
        local slotFrame = _G[slotKey]
        if slotFrame then
            slotFrame:Show()
            if slotFrame.IconBorder then
                slotFrame.IconBorder:SetTexCoord(0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
            end
            local iconTexture = _G[slotKey .. "IconTexture"]
            if iconTexture then
                local z = (CludesUIDB and CludesUIDB.charSheetIconZoom) or 0.07
                iconTexture:SetTexCoord(z, z, z, 1 - z, 1 - z, z, 1 - z, 1 - z)
            end
            local normalTexture = _G[slotKey .. "NormalTexture"]
            if normalTexture then
                normalTexture:Hide()
            end
        end
    end

    -- Re-apply 16/17: the loop above includes the weapon slots and clobbers them.
    do
        local region = select(16, _G.CharacterMainHandSlot:GetRegions())
        if region then
            region:SetTexCoord(0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
        end
    end
    do
        local region = select(17, _G.CharacterMainHandSlot:GetRegions())
        if region then
            region:SetTexCoord(0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
        end
    end
    do
        local region = select(16, _G.CharacterSecondaryHandSlot:GetRegions())
        if region then
            region:SetTexCoord(0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
        end
    end
    do
        local region = select(17, _G.CharacterSecondaryHandSlot:GetRegions())
        if region then
            region:SetTexCoord(0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
        end
    end

    local slotNames = {
        "CharacterHeadSlot",
        "CharacterNeckSlot",
        "CharacterShoulderSlot",
        "CharacterBackSlot",
        "CharacterChestSlot",
        "CharacterShirtSlot",
        "CharacterTabardSlot",
        "CharacterWristSlot",
        "CharacterHandsSlot",
        "CharacterWaistSlot",
        "CharacterLegsSlot",
        "CharacterFeetSlot",
        "CharacterTrinket0Slot",
        "CharacterTrinket1Slot",
        "CharacterFinger0Slot",
        "CharacterFinger1Slot",
        "CharacterMainHandSlot",
        "CharacterSecondaryHandSlot",
    }
    for _, slotKey in ipairs(slotNames) do
        local slotFrame = _G[slotKey]
        if slotFrame then
            slotFrame:Show()
            if GetFFD(slotFrame).slotBg then
                GetFFD(slotFrame).slotBg:SetBlendMode("BLEND")
            end
        end
    end

    -- Scale fully owned by Blizzard (SetScale on secure panels taints UIParentPanelManager execution context).
    widget:SetFrameStrata("HIGH")
    -- The equipment set icon picker inherits HIGH from PaperDollFrame, but its template
    -- keeps the icon grid clickable only by sitting one strata above the rest of the popup.
    -- Restore that gap, or the popup's BG and BorderBox cover the grid.
    local gearPopup = _G.GearManagerPopupFrame
    if gearPopup and gearPopup.IconSelector then
        gearPopup.IconSelector:SetFrameStrata("DIALOG")
    end

    -- Frame size is entirely Blizzard's -- no SetWidth/SetHeight or OnUpdate enforcers on the secure frame; our layout fits inside native dimensions.
    if CharacterFrameInset then
        CharacterFrameInset:SetClipsChildren(false)
    end
    GetFFD(widget).sizeCheckDone = true
end

local function SkinCharacterSheet()
    if skinned then
        return
    end
    skinned = true

    -- Blizz Default (the stock styles below): Blizzard's own frame,
    -- chrome, tabs, slots, model and sidebar panes stay untouched. Only the
    -- stats section (inside Blizzard's stats pane) and the slot text (beside
    -- Blizzard's slots) are built; every art pass below is skipped.
    if not mod.CharSheetStock() then
        PreSkinCharacterSheet()
    end

    local widget = CharacterFrame
    if not widget then
        return
    end

    local FRAME_BG_R, FRAME_BG_G, FRAME_BG_B = 0.03, 0.045, 0.05

    local closeBtn = widget.CloseButton or _G.CharacterFrameCloseButton
    if closeBtn and not mod.CharSheetStock() and mod.WSkin and mod.WSkin.CloseButton then
        mod.WSkin.CloseButton(closeBtn)
    end

    local fontFile = CludesUI.GetFontPath("blizzardSkin") or STANDARD_TEXT_FONT
    local ACC = CludesUI.CLUDES_GREEN or { r = 0.51, g = 0.784, b = 1 }

    do
        -- Stock styles: Blizzard's own model scene, with the label on a
        -- PaperDollFrame child (hides with the Character tab) above the scene's
        -- level and below its rotate/zoom controls (32px tall at TOP -10).
        local stock = mod.CharSheetStock()
        local modelScene = GetFFD(widget).modelScene or (stock and _G.CharacterModelScene)
        if modelScene and not GetFFD(widget).durabilityModelLabel then
            local durOverlay = CreateFrame("Frame", nil, stock and _G.PaperDollFrame or widget)
            durOverlay:SetFrameLevel(modelScene:GetFrameLevel() + 10)
            durOverlay:EnableMouse(false)
            GetFFD(widget).durabilityOverlay = durOverlay

            local durabilityModelLabel = durOverlay:CreateFontString(nil, "OVERLAY")
            durabilityModelLabel:SetFont(fontFile, 12, "")
            durabilityModelLabel:SetPoint("TOP", modelScene, "TOP", 0, stock and -46 or -8)
            GetFFD(widget).durabilityModelLabel = durabilityModelLabel
        end
        if not GetFFD(widget).durabilityFooterLabel then
            local durabilityFooterLabel = widget:CreateFontString(nil, "OVERLAY")
            durabilityFooterLabel:SetFont(fontFile, 12, "")
            GetFFD(widget).durabilityFooterLabel = durabilityFooterLabel
        end
    end

    local charTabs = {}
    for i = 1, 3 do
        local tabBtn = _G["CharacterFrameTab" .. i]
        if tabBtn and not mod.CharSheetStock() then
            charTabs[#charTabs + 1] = tabBtn
            local regionList = { tabBtn:GetRegions() }
            for jdx = 1, #regionList do
                local regionFrame = regionList[jdx]
                if regionFrame and regionFrame:IsObjectType("Texture") then
                    regionFrame:SetTexture("")
                    if regionFrame.SetAtlas then
                        regionFrame:SetAtlas("")
                    end
                end
            end
            if tabBtn.Left then
                tabBtn.Left:SetTexture("")
            end
            if tabBtn.Middle then
                tabBtn.Middle:SetTexture("")
            end
            if tabBtn.Right then
                tabBtn.Right:SetTexture("")
            end
            if tabBtn.LeftDisabled then
                tabBtn.LeftDisabled:SetTexture("")
            end
            if tabBtn.MiddleDisabled then
                tabBtn.MiddleDisabled:SetTexture("")
            end
            if tabBtn.RightDisabled then
                tabBtn.RightDisabled:SetTexture("")
            end
            local highlight = tabBtn:GetHighlightTexture()
            if highlight then
                highlight:SetTexture("")
            end

            if not GetFFD(tabBtn).bg then
                GetFFD(tabBtn).bg = tabBtn:CreateTexture(nil, "BACKGROUND")
                GetFFD(tabBtn).bg:SetAllPoints()
                GetFFD(tabBtn).bg:SetColorTexture(0.068, 0.056, 0.052, 1)
            end

            if not GetFFD(tabBtn).activeHL then
                local activeHighlight = tabBtn:CreateTexture(nil, "ARTWORK", nil, -6)
                activeHighlight:SetAllPoints()
                activeHighlight:SetColorTexture(1, 1, 1, 0.02)
                activeHighlight:SetBlendMode("ADD")
                activeHighlight:Hide()
                GetFFD(tabBtn).activeHL = activeHighlight
            end

            -- Replace Blizzard's label with our own so font/size are under our control.
            local blizLabel = tabBtn:GetFontString()
            local labelText = blizLabel and blizLabel:GetText() or ("Tab " .. i)
            if blizLabel then
                blizLabel:SetTextColor(0, 0, 0, 0)
            end
            tabBtn:SetPushedTextOffset(0, 0)

            if not GetFFD(tabBtn).label then
                local caption = tabBtn:CreateFontString(nil, "OVERLAY")
                caption:SetFont(fontFile, 9, "")
                caption:SetPoint("CENTER", tabBtn, "CENTER", 0, 0)
                caption:SetJustifyH("CENTER")
                caption:SetText(labelText)
                GetFFD(tabBtn).label = caption
                hooksecurefunc(tabBtn, "SetText", function(_, newText)
                    if newText and caption then
                        caption:SetText(newText)
                    end
                end)
            end

            if not GetFFD(tabBtn).underline then
                local underlineTex = tabBtn:CreateTexture(nil, "OVERLAY", nil, 6)
                if CludesUI and CludesUI.PanelPP and CludesUI.PanelPP.DisablePixelSnap then
                    CludesUI.PanelPP.DisablePixelSnap(underlineTex)
                    underlineTex:SetHeight(CludesUI.PanelPP.mult or 1)
                else
                    underlineTex:SetHeight(1)
                end
                underlineTex:SetPoint("BOTTOMLEFT", tabBtn, "BOTTOMLEFT", 0, 0)
                underlineTex:SetPoint("BOTTOMRIGHT", tabBtn, "BOTTOMRIGHT", 0, 0)
                underlineTex:SetColorTexture(ACC.r or 0.51, ACC.g or 0.784, ACC.b or 1, 1)
                CludesUI.RegAccent({ type = "solid", obj = underlineTex, a = 1 })
                underlineTex:Hide()
                GetFFD(tabBtn).underline = underlineTex
            end
        end
    end
    -- Uniform one-physical-pixel seam between bottom tabs, as in every other themed window (raw CharacterFrameTab frames sit further apart).
    if mod.WSkin and mod.WSkin.NormalizeTabRow and #charTabs > 0 then
        mod.WSkin.NormalizeTabRow(charTabs)
    end

    local function UpdateTabVisuals()
        for i = 1, 3 do
            local tabBtn = _G["CharacterFrameTab" .. i]
            if tabBtn then
                -- PanelTemplates_GetSelectedTab is unreliable here -- Blizzard updates frame.selectedTab before the template helper agrees.
                local isActive = (widget.selectedTab or 1) == i
                if GetFFD(tabBtn).label then
                    GetFFD(tabBtn).label:SetTextColor(1, 1, 1, isActive and 1 or 0.5)
                end
                if GetFFD(tabBtn).underline then
                    GetFFD(tabBtn).underline:SetShown(isActive)
                end
                if GetFFD(tabBtn).activeHL then
                    GetFFD(tabBtn).activeHL:SetShown(isActive)
                end
            end
        end
    end

    -- Faint background on the Reputation + Currency panes, idempotent. Anchored to the inner
    -- ScrollBox so it stays in the list area and never bleeds over the tab chrome.
    local function _ensureTabBg(panel)
        if not panel or GetFFD(panel).bg then
            return
        end
        local anchorFrame = panel.ScrollBox or panel.scrollFrame or panel
        local texture = panel:CreateTexture(nil, "BACKGROUND", nil, -7)
        texture:SetColorTexture(0, 0, 0, 0.1)
        texture:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", 10, -10)
        texture:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", -10, 0)
        GetFFD(panel).bg = texture
    end
    if not mod.CharSheetStock() then
        _ensureTabBg(_G.ReputationFrame)
        _ensureTabBg(_G.TokenFrame)
    end

    -- Tab visibility dispatcher: hook each sub-pane's OnShow (Blizzard drives visibility, we react)
    -- instead of intercepting PanelTemplates_SetTab. Pane OnShow runs inside the secure ShowSubFrame
    -- path, where explicit :Show()/:Hide() (even on our own named frames) flags as a protected call; SetShown does not, so every toggle below uses SetShown.
    -- Stock styles need none of it: everything they build is parented under
    -- PaperDollFrame / CharacterStatsPane, so Blizzard's own tab and sidebar
    -- code shows and hides it, and no Blizzard slot is ever shown or hidden.
    local function ApplyTabVisibility(isCharacterTab)
        if mod.CharSheetStock() then
            return
        end
        UpdateTabVisuals()

        if GetFFD(widget).themedSlots then
            for _, slotKey in ipairs(GetFFD(widget).themedSlots) do
                local slotFrame = _G[slotKey]
                if slotFrame then
                    slotFrame:SetShown(isCharacterTab)
                    if GetFFD(slotFrame).itemLevelLabel then
                        GetFFD(slotFrame).itemLevelLabel:SetShown(isCharacterTab)
                    end
                    if GetFFD(slotFrame).enchantLabel then
                        GetFFD(slotFrame).enchantLabel:SetShown(isCharacterTab)
                    end
                    if GetFFD(slotFrame).enchantHoverFrame then
                        GetFFD(slotFrame).enchantHoverFrame:SetShown(isCharacterTab)
                    end
                    if GetFFD(slotFrame).upgradeTrackLabel then
                        GetFFD(slotFrame).upgradeTrackLabel:SetShown(isCharacterTab)
                    end
                    if GetFFD(slotFrame).statLetterLabel then
                        GetFFD(slotFrame).statLetterLabel:SetShown(isCharacterTab)
                    end
                    if GetFFD(slotFrame).statLetterTerLabel then
                        GetFFD(slotFrame).statLetterTerLabel:SetShown(isCharacterTab)
                    end
                end
            end
        end

        for _, btnName in ipairs({ "CUI_CharSheet_Stats", "CUI_CharSheet_Titles", "CUI_CharSheet_Equipment" }) do
            local btnFrame = _G[btnName]
            if btnFrame then
                btnFrame:SetShown(isCharacterTab)
            end
        end

        if GetFFD(widget).modelBgFrame then
            GetFFD(widget).modelBgFrame:SetShown(isCharacterTab)
        end
        -- The Stats and Titles panels follow Blizzard's sidebar pane they stand
        -- in for (see SyncTopButtons); off every other tab.
        local statsPane = _G.CharacterStatsPane
        local titlesPane = _G.PaperDollFrame and _G.PaperDollFrame.TitleManagerPane
        if GetFFD(widget).statsPanel then
            GetFFD(widget).statsPanel:SetShown(isCharacterTab and (statsPane == nil or statsPane:IsShown()))
        end
        if GetFFD(widget).titlesPanel then
            GetFFD(widget).titlesPanel:SetShown(isCharacterTab and titlesPane ~= nil and titlesPane:IsShown())
        end
        if GetFFD(widget).iLvlText then
            GetFFD(widget).iLvlText:SetShown(isCharacterTab)
        end
        if GetFFD(widget).sidebarBgFrame then
            GetFFD(widget).sidebarBgFrame:SetShown(isCharacterTab)
        end
        if GetFFD(widget).scrollFrame then
            GetFFD(widget).scrollFrame:SetShown(isCharacterTab)
        end
        if GetFFD(widget).scrollBar then
            GetFFD(widget).scrollBar:SetShown(isCharacterTab)
        end
        if GetFFD(widget).socketContainer then
            GetFFD(widget).socketContainer:SetShown(isCharacterTab)
        end

        if GetFFD(widget).statsSections then
            for _, sectionInfo in ipairs(GetFFD(widget).statsSections) do
                if sectionInfo.container then
                    sectionInfo.container:SetShown(isCharacterTab)
                end
            end
        end

        if GetFFD(widget).modelScene then
            GetFFD(widget).modelScene:SetShown(isCharacterTab)
        end
        if GetFFD(widget).modelBgFrame then
            GetFFD(widget).modelBgFrame:SetShown(isCharacterTab)
        end
        if CludesUI._updateCharSheetDurability then
            CludesUI._updateCharSheetDurability()
        end
    end

    local function _hookPaneOnShow(panel, isChar)
        if not panel then
            return
        end
        panel:HookScript("OnShow", function()
            _ensureTabBg(_G.ReputationFrame)
            _ensureTabBg(_G.TokenFrame)
            ApplyTabVisibility(isChar)
        end)
    end
    if not mod.CharSheetStock() then
        _hookPaneOnShow(_G.PaperDollFrame, true)
        _hookPaneOnShow(_G.ReputationFrame, false)
        _hookPaneOnShow(_G.TokenFrame, false)
    end

    ApplyTabVisibility((widget.selectedTab or 1) == 1)

    local statsPane
    if mod.CharSheetStock() then
        -- Stock styles: a child of Blizzard's stats pane (parked off-screen at
        -- login, see the init below) laid over the pane's own InsetRight slot,
        -- so the stats sidebar tab, Collapse/Expand and the Titles/Equipment
        -- sidebar tabs show and hide it natively. InsetRight keeps its own
        -- inset background, so no backdrop of ours.
        local panel = _G.CharacterStatsPane
        -- The login pass parks the pane only when the sheet skin was on at
        -- login; a skin turned on mid-session (reload declined) parks it here.
        mod.CharSheetParkStatsPane()
        local inset = widget.InsetRight or _G.CharacterFrameInsetRight
        statsPane = CreateFrame("Frame", "CUI_CharSheet_StatsPanel", panel or widget)
        statsPane:SetPoint("TOPLEFT", inset or widget, "TOPLEFT", 3, -3)
        statsPane:SetPoint("BOTTOMRIGHT", inset or widget, "BOTTOMRIGHT", -3, 2)
        statsPane:SetFrameLevel((panel or widget):GetFrameLevel() + 5)
    else
        -- Stats panel: fixed-width column pinned down the right of the sheet.
        statsPane = CreateFrame("Frame", "CUI_CharSheet_StatsPanel", widget)
        statsPane:SetWidth(190)
        statsPane:SetPoint("TOPLEFT", widget, "TOPLEFT", 345, -60)
        statsPane:SetPoint("BOTTOMLEFT", widget, "BOTTOMLEFT", 345, 40)
        statsPane:SetFrameLevel(50)

        -- Sidebar background lives on frame (not statsPanel) so it stays visible across Character/Titles/Equipment panels.
        local sidebarBgFrame = CreateFrame("Frame", nil, widget)
        sidebarBgFrame:SetFrameLevel(statsPane:GetFrameLevel() - 1)
        sidebarBgFrame:SetPoint("TOPLEFT", statsPane, "TOPLEFT", -51, 10)
        sidebarBgFrame:SetPoint("BOTTOMRIGHT", statsPane, "BOTTOMRIGHT", 0, -10)
        local statsBg = sidebarBgFrame:CreateTexture(nil, "BACKGROUND")
        statsBg:SetColorTexture(0, 0, 0, 0.2)
        statsBg:SetAllPoints()
        GetFFD(widget).statsBg = statsBg
        GetFFD(widget).sidebarBgFrame = sidebarBgFrame
    end

    local INVTYPE_TO_SLOT = {
        INVTYPE_HEAD = { slot = 1, name = "Head" },
        INVTYPE_NECK = { slot = 2, name = "Neck" },
        INVTYPE_SHOULDER = { slot = 3, name = "Shoulder" },
        INVTYPE_CHEST = { slot = 5, name = "Chest" },
        -- Cloth robes report INVTYPE_ROBE instead of INVTYPE_CHEST -- same slot.
        INVTYPE_ROBE = { slot = 5, name = "Chest" },
        INVTYPE_WAIST = { slot = 6, name = "Waist" },
        INVTYPE_LEGS = { slot = 7, name = "Legs" },
        INVTYPE_FEET = { slot = 8, name = "Feet" },
        INVTYPE_WRIST = { slot = 9, name = "Wrist" },
        INVTYPE_HAND = { slot = 10, name = "Hands" },
        INVTYPE_FINGER = { slots = { 11, 12 }, name = "Ring" },
        INVTYPE_TRINKET = { slots = { 13, 14 }, name = "Trinket" },
        -- A cloak's equip-location string is INVTYPE_CLOAK, never INVTYPE_BACK.
        -- "Cloak" (not "Back") so this doesn't collide with the "Back" nav-button
        -- key elsewhere in the catalog; matches CUI_UpgradeCalc.lua's slotNames[15].
        INVTYPE_CLOAK = { slot = 15, name = "Cloak" },
        -- One-hand weapons report INVTYPE_WEAPONMAINHAND / INVTYPE_WEAPONOFFHAND;
        -- INVTYPE_MAINHAND / INVTYPE_OFFHAND do not exist and match no item. An
        -- ambiguous one-hander (INVTYPE_WEAPON) can go in either slot.
        INVTYPE_WEAPON = { slots = { 16, 17 }, name = "Weapon" },
        INVTYPE_WEAPONMAINHAND = { slot = 16, name = "Main Hand" },
        INVTYPE_WEAPONOFFHAND = { slot = 17, name = "Off Hand" },
        -- Caster off-hands (tomes/orbs); the slot mapping is what lets them reach
        -- the allow.offhand gate in IsItemUsableBySpec.
        INVTYPE_HOLDABLE = { slot = 17, name = "Off Hand" },
        -- Bows/guns/crossbows/wands report these equip locations even though they
        -- physically equip into the main-hand slot.
        INVTYPE_RANGEDRIGHT = { slot = 16, name = "Main Hand" },
        INVTYPE_RANGED = { slot = 16, name = "Main Hand" },
        INVTYPE_RELIC = { slot = 18, name = "Relic" },
        INVTYPE_BODY = { slot = 4, name = "Body" },
        INVTYPE_SHIELD = { slot = 17, name = "Shield" },
        INVTYPE_2HWEAPON = { slot = 16, name = "Two-Hand" },
    }

    -- Item level of the equipped item. GetItemInfo's cached itemLevel can be wrong for a
    -- specific instance (upgrade-track pieces); prefer ItemLocation (exact, uncached) then GetDetailedItemLevelInfo -- same precedence as CludesUIQoL.lua.
    local function GetEquippedItemLevel(slotFrame)
        if ItemLocation then
            local itemLocation = ItemLocation:CreateFromEquipmentSlot(slotFrame)
            if itemLocation and itemLocation:IsValid() and C_Item.DoesItemExist(itemLocation) then
                return C_Item.GetCurrentItemLevel(itemLocation) or 0
            end
        end
        local linkText = GetInventoryItemLink("player", slotFrame)
        if linkText then
            return C_Item.GetDetailedItemLevelInfo(linkText) or 0
        end
        return 0
    end

    ---------------------------------------------------------------------------
    -- Spec-aware "better item" filter: hardcoded allowlist of weapon subclasses +
    -- shield/offhand usability per spec, so a higher-ilvl but unusable piece (a
    -- shield for Ret, a 2H polearm for Prot) never counts as an upgrade.
    --
    -- Weapon subclass IDs (Enum.ItemWeaponSubclass):
    --   0  Axe1H     1  Axe2H       2  Bow       3  Gun
    --   4  Mace1H    5  Mace2H      6  Polearm   7  Sword1H
    --   8  Sword2H   9  Warglaive   10 Staff     13 Fist
    --   15 Dagger    18 Crossbow    19 Wand
    ---------------------------------------------------------------------------
    local W_AXE1H, W_AXE2H = 0, 1
    local W_BOW, W_GUN = 2, 3
    local W_MACE1H, W_MACE2H = 4, 5
    local W_POLEARM = 6
    local W_SWORD1H, W_SWORD2H = 7, 8
    local W_WARGLAIVE = 9
    local W_STAFF = 10
    local W_FIST = 13
    local W_DAGGER = 15
    local W_CROSSBOW = 18
    local W_WAND = 19

    -- Armor subclasses
    local A_MISC, A_CLOTH, A_LEATHER, A_MAIL, A_PLATE = 0, 1, 2, 3, 4
    local A_SHIELD = 6

    -- Class -> top armor proficiency. Lower tiers are ignored since wearing
    -- below-proficiency armor is never an upgrade for these specs.
    local CLASS_ARMOR = {
        PALADIN = A_PLATE,
        DEATHKNIGHT = A_PLATE,
        WARRIOR = A_PLATE,
        HUNTER = A_MAIL,
        SHAMAN = A_MAIL,
        EVOKER = A_MAIL,
        DRUID = A_LEATHER,
        MONK = A_LEATHER,
        ROGUE = A_LEATHER,
        DEMONHUNTER = A_LEATHER,
        MAGE = A_CLOTH,
        PRIEST = A_CLOTH,
        WARLOCK = A_CLOTH,
    }

    -- Per-spec weapon + shield/offhand usability.
    local SPEC_EQUIP = {
        -- Death Knight
        [250] = { weapons = { [W_AXE2H] = 1, [W_MACE2H] = 1, [W_SWORD2H] = 1, [W_POLEARM] = 1 } }, -- Blood
        [251] = { weapons = { [W_AXE1H] = 1, [W_MACE1H] = 1, [W_SWORD1H] = 1 } }, -- Frost (DW 1H)
        [252] = { weapons = { [W_AXE2H] = 1, [W_MACE2H] = 1, [W_SWORD2H] = 1, [W_POLEARM] = 1 } }, -- Unholy
        -- Demon Hunter
        [577] = { weapons = { [W_WARGLAIVE] = 1, [W_AXE1H] = 1, [W_SWORD1H] = 1, [W_FIST] = 1 } }, -- Havoc
        [581] = { weapons = { [W_WARGLAIVE] = 1, [W_AXE1H] = 1, [W_SWORD1H] = 1, [W_FIST] = 1 } }, -- Vengeance
        -- Druid
        [102] = {
            weapons = { [W_STAFF] = 1, [W_POLEARM] = 1, [W_MACE2H] = 1, [W_DAGGER] = 1, [W_MACE1H] = 1 },
            offhand = true,
        }, -- Balance
        [103] = { weapons = { [W_STAFF] = 1, [W_POLEARM] = 1, [W_MACE2H] = 1, [W_FIST] = 1 } }, -- Feral
        [104] = { weapons = { [W_STAFF] = 1, [W_POLEARM] = 1, [W_MACE2H] = 1 } }, -- Guardian
        [105] = {
            weapons = { [W_STAFF] = 1, [W_MACE2H] = 1, [W_POLEARM] = 1, [W_MACE1H] = 1, [W_DAGGER] = 1 },
            offhand = true,
        }, -- Resto
        -- Hunter
        [253] = { weapons = { [W_BOW] = 1, [W_GUN] = 1, [W_CROSSBOW] = 1 } }, -- BM
        [254] = { weapons = { [W_BOW] = 1, [W_GUN] = 1, [W_CROSSBOW] = 1 } }, -- MM
        [255] = { weapons = { [W_POLEARM] = 1, [W_SWORD2H] = 1, [W_AXE2H] = 1 } }, -- Survival
        -- Mage
        [62] = { weapons = { [W_STAFF] = 1, [W_DAGGER] = 1, [W_SWORD1H] = 1, [W_WAND] = 1 }, offhand = true }, -- Arcane
        [63] = { weapons = { [W_STAFF] = 1, [W_DAGGER] = 1, [W_SWORD1H] = 1, [W_WAND] = 1 }, offhand = true }, -- Fire
        [64] = { weapons = { [W_STAFF] = 1, [W_DAGGER] = 1, [W_SWORD1H] = 1, [W_WAND] = 1 }, offhand = true }, -- Frost
        -- Monk
        [268] = {
            weapons = {
                [W_STAFF] = 1,
                [W_POLEARM] = 1,
                [W_FIST] = 1,
                [W_AXE1H] = 1,
                [W_MACE1H] = 1,
                [W_SWORD1H] = 1,
            },
            offhand = true,
        }, -- Brewmaster
        [269] = {
            weapons = {
                [W_FIST] = 1,
                [W_AXE1H] = 1,
                [W_MACE1H] = 1,
                [W_SWORD1H] = 1,
                [W_STAFF] = 1,
                [W_POLEARM] = 1,
            },
            offhand = true,
        }, -- Windwalker
        [270] = {
            weapons = { [W_STAFF] = 1, [W_FIST] = 1, [W_AXE1H] = 1, [W_MACE1H] = 1, [W_SWORD1H] = 1 },
            offhand = true,
        }, -- Mistweaver
        -- Paladin
        [65] = { weapons = { [W_MACE1H] = 1, [W_SWORD1H] = 1, [W_AXE1H] = 1 }, shield = true, offhand = true }, -- Holy
        [66] = { weapons = { [W_MACE1H] = 1, [W_SWORD1H] = 1, [W_AXE1H] = 1 }, shield = true }, -- Prot
        [70] = {
            weapons = {
                [W_MACE2H] = 1,
                [W_SWORD2H] = 1,
                [W_AXE2H] = 1,
                [W_POLEARM] = 1,
                [W_MACE1H] = 1,
                [W_SWORD1H] = 1,
                [W_AXE1H] = 1,
            },
        }, -- Ret (2H or DW 1H)
        -- Priest
        [256] = { weapons = { [W_STAFF] = 1, [W_WAND] = 1, [W_DAGGER] = 1, [W_MACE1H] = 1 }, offhand = true }, -- Disc
        [257] = { weapons = { [W_STAFF] = 1, [W_WAND] = 1, [W_DAGGER] = 1, [W_MACE1H] = 1 }, offhand = true }, -- Holy
        [258] = { weapons = { [W_STAFF] = 1, [W_WAND] = 1, [W_DAGGER] = 1, [W_MACE1H] = 1 }, offhand = true }, -- Shadow
        -- Rogue
        [259] = { weapons = { [W_DAGGER] = 1 } }, -- Assassination
        [260] = { weapons = { [W_SWORD1H] = 1, [W_MACE1H] = 1, [W_AXE1H] = 1, [W_FIST] = 1, [W_DAGGER] = 1 } }, -- Outlaw
        [261] = { weapons = { [W_DAGGER] = 1 } }, -- Subtlety
        -- Shaman
        [262] = {
            weapons = { [W_STAFF] = 1, [W_MACE1H] = 1, [W_AXE1H] = 1, [W_DAGGER] = 1 },
            shield = true,
            offhand = true,
        }, -- Elemental
        [263] = { weapons = { [W_MACE1H] = 1, [W_AXE1H] = 1, [W_FIST] = 1 } }, -- Enhancement (DW 1H)
        [264] = {
            weapons = { [W_STAFF] = 1, [W_MACE1H] = 1, [W_AXE1H] = 1, [W_DAGGER] = 1 },
            shield = true,
            offhand = true,
        }, -- Resto
        -- Warlock
        [265] = { weapons = { [W_STAFF] = 1, [W_WAND] = 1, [W_DAGGER] = 1, [W_SWORD1H] = 1 }, offhand = true }, -- Affliction
        [266] = { weapons = { [W_STAFF] = 1, [W_WAND] = 1, [W_DAGGER] = 1, [W_SWORD1H] = 1 }, offhand = true }, -- Demonology
        [267] = { weapons = { [W_STAFF] = 1, [W_WAND] = 1, [W_DAGGER] = 1, [W_SWORD1H] = 1 }, offhand = true }, -- Destruction
        -- Warrior
        [71] = { weapons = { [W_AXE2H] = 1, [W_MACE2H] = 1, [W_SWORD2H] = 1, [W_POLEARM] = 1 } }, -- Arms
        [72] = {
            weapons = {
                [W_AXE1H] = 1,
                [W_MACE1H] = 1,
                [W_SWORD1H] = 1,
                [W_AXE2H] = 1,
                [W_MACE2H] = 1,
                [W_SWORD2H] = 1,
                [W_POLEARM] = 1,
            },
        }, -- Fury
        [73] = { weapons = { [W_AXE1H] = 1, [W_MACE1H] = 1, [W_SWORD1H] = 1 }, shield = true }, -- Prot
        -- Evoker
        [1467] = {
            weapons = {
                [W_STAFF] = 1,
                [W_POLEARM] = 1,
                [W_MACE1H] = 1,
                [W_SWORD1H] = 1,
                [W_DAGGER] = 1,
                [W_FIST] = 1,
            },
            offhand = true,
        },
        [1468] = {
            weapons = {
                [W_STAFF] = 1,
                [W_POLEARM] = 1,
                [W_MACE1H] = 1,
                [W_SWORD1H] = 1,
                [W_DAGGER] = 1,
                [W_FIST] = 1,
            },
            offhand = true,
        },
        [1473] = {
            weapons = {
                [W_STAFF] = 1,
                [W_POLEARM] = 1,
                [W_MACE1H] = 1,
                [W_SWORD1H] = 1,
                [W_DAGGER] = 1,
                [W_FIST] = 1,
            },
            offhand = true,
        },
    }

    -- Returns true if the given item is appropriate for the player's current spec.
    -- Only weapons, shields, and armor are gated; rings/trinkets/necks/cloaks pass.
    local function IsItemUsableBySpec(linkText, equipLoc, classID, subclassID)
        local specIdx = GetSpecialization and GetSpecialization()
        local specID = specIdx and GetSpecializationInfo(specIdx)
        local allow = specID and SPEC_EQUIP[specID]
        if not allow then
            return true
        end -- unknown spec: don't filter

        -- Weapons (classID 2): subclass must be in the spec's allowed set.
        if classID == 2 then
            return allow.weapons and allow.weapons[subclassID] == 1 or false
        end

        -- Armor (classID 4): shields and holdable offhands are spec-gated;
        -- other armor pieces must match the class's top armor proficiency.
        if classID == 4 then
            if subclassID == A_SHIELD then
                return allow.shield == true
            end
            if equipLoc == "INVTYPE_HOLDABLE" then
                return allow.offhand == true
            end
            -- Tabards, shirts, cloaks (Misc) are always allowed.
            if
                subclassID == A_MISC
                or equipLoc == "INVTYPE_TABARD"
                or equipLoc == "INVTYPE_BODY"
                or equipLoc == "INVTYPE_CLOAK"
            then
                return true
            end
            local _, playerClass = UnitClass("player")
            local topArmor = CLASS_ARMOR[playerClass]
            if topArmor and subclassID ~= topArmor then
                return false
            end
        end

        return true
    end

    -- Cached scan of bag items that are upgrades over equipped gear. Dirtied by the
    -- iLvlUpdateFrame handler below (PLAYER_EQUIPMENT_CHANGED, BAG_UPDATE etc) and by CharacterFrame OnShow, only while the sheet is open.
    local _betterCache = nil
    local _betterDirty = true

    local _ComputeBetterInventoryItems -- defined below

    local function GetBetterInventoryItems()
        if _betterDirty or not _betterCache then
            _betterCache = _ComputeBetterInventoryItems()
            _betterDirty = false
        end
        return _betterCache
    end

    _ComputeBetterInventoryItems = function()
        local upgrades = {}
        local canDualWield = CanDualWield()

        -- A 2H main-hand leaves slot 17 empty, so GetEquippedItemLevel(17)=0 and any
        -- off-hand/holdable/shield in bags reads as a false upgrade. Suppress slot-17
        -- comparisons while off-hand is truly empty (Titan's Grip keeps a real item there, comparing normally).
        local offHandBlocked = false
        do
            local mhLink = GetInventoryItemLink("player", 16)
            if mhLink and GetInventoryItemLink("player", 17) == nil then
                local _, _, _, mhEquipLoc = C_Item.GetItemInfoInstant(mhLink)
                if
                    mhEquipLoc == "INVTYPE_2HWEAPON"
                    or mhEquipLoc == "INVTYPE_RANGED"
                    or mhEquipLoc == "INVTYPE_RANGEDRIGHT"
                then
                    offHandBlocked = true
                end
            end
        end

        -- Check all bag slots (0 = backpack, 1-4 = bag slots, 5 = reagent
        -- bag -- included since it can hold any item, not just reagents).
        for bagSlot = 0, 5 do
            local bagSize = C_Container.GetContainerNumSlots(bagSlot)
            for slotIndex = 1, bagSize do
                local linkText = C_Container.GetContainerItemLink(bagSlot, slotIndex)
                if linkText then
                    local itemName, _, itemRarity, _, _, _, _, _, equipSlot, itemIcon =
                        C_Item.GetItemInfo(linkText)
                    -- ItemLocation first (exact, uncached); GetItemInfo's cached itemLevel
                    -- can be stale for a specific instance.
                    local levelValue
                    if ItemLocation then
                        local itemLocation = ItemLocation:CreateFromBagAndSlot(bagSlot, slotIndex)
                        if itemLocation and itemLocation:IsValid() and C_Item.DoesItemExist(itemLocation) then
                            levelValue = C_Item.GetCurrentItemLevel(itemLocation)
                        end
                    end
                    levelValue = tonumber(levelValue) or tonumber(C_Item.GetDetailedItemLevelInfo(linkText))

                    -- Weapons/armor only, matched via GetItemInfoInstant's locale-independent
                    -- classID/subclassID (Weapon=2, Armor=4) -- GetItemInfo's itemType/itemSubType
                    -- are localized display strings and would filter out non-English clients.
                    -- GetItemInfoInstant returns: 1 itemID, 2 itemType, 3 itemSubType, 4 itemEquipLoc, 5 iconFileID, 6 classID, 7 subClassID.
                    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(linkText)
                    if
                        levelValue
                        and itemName
                        and (classID == Enum.ItemClass.Weapon or classID == Enum.ItemClass.Armor)
                        and equipSlot
                    then
                        -- Spec-aware usability filter (skip shields on Ret, etc.)
                        if not IsItemUsableBySpec(linkText, equipSlot, classID, subclassID) then
                            -- skip: not usable by current spec
                        else
                            local slotInfo = INVTYPE_TO_SLOT[equipSlot]
                            if slotInfo then
                                local isBetter = false
                                local compareSlots = slotInfo.slots or { slotInfo.slot }
                                local offHandWeaponBlocked = not canDualWield
                                    and (
                                        equipSlot == "INVTYPE_WEAPON"
                                        or equipSlot == "INVTYPE_WEAPONOFFHAND"
                                    )

                                for _, slotFrame in ipairs(compareSlots) do
                                    -- A one-hander cannot replace a shield/held item without dual wield.
                                    if not (slotFrame == 17 and (offHandBlocked or offHandWeaponBlocked)) then
                                        local equippedLevel = GetEquippedItemLevel(slotFrame)
                                        if levelValue > equippedLevel then
                                            isBetter = true
                                            break
                                        end
                                    end
                                end

                                if isBetter then
                                    table.insert(upgrades, {
                                        name = itemName,
                                        level = levelValue,
                                        rarity = itemRarity or 1,
                                        icon = itemIcon,
                                        slot = slotInfo.name,
                                    })
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Keep only the single highest-ilvl candidate per slot
        local bestPerSlot = {}
        for _, entry in ipairs(upgrades) do
            local current = bestPerSlot[entry.slot]
            if not current or entry.level > current.level then
                bestPerSlot[entry.slot] = entry
            end
        end
        local deduped = {}
        for _, entry in pairs(bestPerSlot) do
            deduped[#deduped + 1] = entry
        end

        table.sort(deduped, function(a, button)
            return a.level > button.level
        end)

        return deduped
    end

    -- M+ Score display (single inline FontString above itemlevel), colored via |cff...|r escapes based on score brackets.
    local mythicRatingLabel = statsPane:CreateFontString(nil, "OVERLAY")
    mythicRatingLabel:SetFont(fontFile, 12, "")
    -- Positioned below iLvlText once that FontString exists (see below).
    mythicRatingLabel:SetTextColor(0.8, 0.8, 0.8, 1)
    mythicRatingLabel:SetText(L("M+ Score:"))
    GetFFD(widget).mythicRatingLabel = mythicRatingLabel

    -- Alias for call sites that test the value FontString; the label hosts both parts.
    GetFFD(widget).mythicRatingValue = mythicRatingLabel

    -- Itemlevel display: sits just below the 3 tab buttons, inside the panel.
    local iLvlText = statsPane:CreateFontString(nil, "OVERLAY")
    iLvlText:SetFont(fontFile, 18, "")
    -- buttonHeight(25) + 3 gap; the stock styles have no button row (Blizzard's
    -- own sidebar tabs sit above the pane).
    iLvlText:SetPoint("TOP", statsPane, "TOP", 0, mod.CharSheetStock() and -8 or -(25 + 3))
    do
        -- Stock styles' "Blizzard UI Color" puts the item level in Blizzard's yellow.
        local blz = mod.CharSheetBlizzColor()
        if blz then
            iLvlText:SetTextColor(blz.r, blz.g, blz.b, 1)
        else
            iLvlText:SetTextColor(0.6, 0.2, 1, 1)
        end
    end
    GetFFD(widget).iLvlText = iLvlText -- Store for tab visibility control

    -- PvP Item Level: sits directly below the iLvl text when enabled.
    local pvpIlvlText = statsPane:CreateFontString(nil, "OVERLAY")
    pvpIlvlText:SetFont(fontFile, 12, "")
    pvpIlvlText:SetTextColor(0.8, 0.8, 0.8, 1)
    pvpIlvlText:SetPoint("TOP", iLvlText, "BOTTOM", 0, -4)
    pvpIlvlText:Hide()
    GetFFD(widget).pvpIlvlText = pvpIlvlText

    -- M+ Score sits below PvP ilvl (or iLvl if PvP is hidden).
    mythicRatingLabel:SetPoint("TOP", pvpIlvlText, "BOTTOM", 0, -4)

    local durabilityHeaderLabel = statsPane:CreateFontString(nil, "OVERLAY")
    durabilityHeaderLabel:SetFont(fontFile, 12, "")
    durabilityHeaderLabel:Hide()
    GetFFD(widget).durabilityHeaderLabel = durabilityHeaderLabel

    local function GetDurabilityHeaderAnchor()
        local frameData = GetFFD(widget)
        if frameData.mythicRatingLabel and frameData.mythicRatingLabel:IsShown() then
            return frameData.mythicRatingLabel
        end
        if frameData.pvpIlvlText and frameData.pvpIlvlText:IsShown() then
            return frameData.pvpIlvlText
        end
        return frameData.iLvlText
    end

    local function AnchorDurabilityFooterLabel(footerText)
        if not footerText then
            return
        end
        footerText:ClearAllPoints()
        local socketPanel = _G.CUI_CharSheet_SocketPanel
        local seasonPanel = _G.CUI_CharSheet_SeasonPanel
        if socketPanel and socketPanel:IsShown() then
            footerText:SetPoint("RIGHT", socketPanel, "LEFT", -8, 0)
        elseif seasonPanel and seasonPanel:IsShown() then
            footerText:SetPoint("RIGHT", seasonPanel, "LEFT", -8, 0)
        else
            footerText:SetPoint("RIGHT", widget, "BOTTOMRIGHT", -10, 6)
        end
    end

    -- Labels are created once above (model/footer at skin time, header just
    -- above); the ffd handle is stable, so no per-call lookups or closures.
    local durFfd = GetFFD(widget)
    local function HideAllDurabilityLabels()
        if durFfd.durabilityModelLabel then
            durFfd.durabilityModelLabel:Hide()
        end
        if durFfd.durabilityHeaderLabel then
            durFfd.durabilityHeaderLabel:Hide()
        end
        if durFfd.durabilityFooterLabel then
            durFfd.durabilityFooterLabel:Hide()
        end
        if durFfd.durabilityOverlay then
            durFfd.durabilityOverlay:Hide()
        end
    end

    -- Zero cost while off or closed: the durability event is registered only
    -- while the feature is enabled AND the sheet is shown (OnShow/OnHide +
    -- the options toggle re-sync); the OnShow pass paints the first value.
    local durabilityWatch
    local UpdateDurabilityDisplay
    local function SyncDurabilityEvents()
        local wanted = CludesUIDB and CludesUIDB.showCharSheetDurability and widget:IsShown()
        if wanted then
            if not durabilityWatch then
                durabilityWatch = CreateFrame("Frame")
                durabilityWatch:SetScript("OnEvent", function()
                    UpdateDurabilityDisplay()
                end)
            end
            durabilityWatch:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
            -- Self-repair items recalculate alerts without firing the durability
            -- event (Blizzard's DurabilityFrame itself rides the alert event).
            durabilityWatch:RegisterEvent("UPDATE_INVENTORY_ALERTS")
        elseif durabilityWatch then
            durabilityWatch:UnregisterEvent("UPDATE_INVENTORY_DURABILITY")
            durabilityWatch:UnregisterEvent("UPDATE_INVENTORY_ALERTS")
        end
    end

    UpdateDurabilityDisplay = function()
        SyncDurabilityEvents()
        -- Stock styles: the labels ride Blizzard's own panes (the stats pane,
        -- the PaperDollFrame overlay), whose tab code shows and hides them.
        if
            not (CludesUIDB and CludesUIDB.showCharSheetDurability)
            or not (mod.CharSheetStock() or (PaperDollFrame and PaperDollFrame:IsShown()))
        then
            HideAllDurabilityLabels()
            return
        end

        local modelLabel = durFfd.durabilityModelLabel
        local headerLabel = durFfd.durabilityHeaderLabel
        local footerText = durFfd.durabilityFooterLabel
        local overlayFrame = durFfd.durabilityOverlay
        local location = CludesUIDB.charSheetDurabilityLocation or "model"
        -- Blizzard's own frame has no free footer strip: the stock styles show
        -- a Frame Footer pick in the stats header instead.
        if location == "footer" and mod.CharSheetStock() then
            location = "header"
        end
        local showLabel = CludesUIDB.charSheetDurabilityShowLabel ~= false
        local percent = GetDurabilityPercent()
        local region, g, button = GetDurabilityTextColor(percent)
        local textValue = FormatDurabilityText(percent, showLabel)

        HideAllDurabilityLabels()

        if location == "header" and headerLabel then
            local anchorFrame = GetDurabilityHeaderAnchor()
            if anchorFrame then
                headerLabel:ClearAllPoints()
                headerLabel:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -4)
            end
            headerLabel:SetText(textValue)
            headerLabel:SetTextColor(region, g, button, 1)
            headerLabel:Show()
        elseif location == "footer" and footerText then
            AnchorDurabilityFooterLabel(footerText)
            footerText:SetText(textValue)
            footerText:SetTextColor(region, g, button, 1)
            footerText:Show()
        elseif modelLabel then
            modelLabel:SetText(textValue)
            modelLabel:SetTextColor(region, g, button, 1)
            modelLabel:Show()
            if overlayFrame then
                overlayFrame:Show()
            end
        end
    end

    CludesUI._updateCharSheetDurability = UpdateDurabilityDisplay

    -- SkinCharacterSheet runs once (guarded), so these hooks install once.
    widget:HookScript("OnShow", UpdateDurabilityDisplay)
    widget:HookScript("OnHide", SyncDurabilityEvents)

    UpdateDurabilityDisplay()

    -- Button overlay for itemlevel tooltip
    local iLvlButton = CreateFrame("Button", nil, statsPane)
    iLvlButton:SetPoint("TOPLEFT", iLvlText, "TOPLEFT", -10, 4)
    iLvlButton:SetPoint("BOTTOMRIGHT", iLvlText, "BOTTOMRIGHT", 10, -4)
    iLvlButton:SetFrameLevel(statsPane:GetFrameLevel() + 3)
    iLvlButton:EnableMouse(true)
    iLvlButton:SetScript("OnEnter", function(self)
        local upgrades = GetBetterInventoryItems()

        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L("Equipped Item Level"), 0.6, 0.2, 1, 1)

        if #upgrades > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(
                string.format(
                    L("You have %d better item%s in inventory"),
                    #upgrades,
                    #upgrades == 1 and "" or "s"
                ),
                0.2,
                1,
                0.2
            )
            GameTooltip:AddLine(" ")

            -- Show up to 10 items with icons and slots (slot on right side)
            local maxShow = math.min(#upgrades, 10)
            for i = 1, maxShow do
                local entry = upgrades[i]
                local leftText = string.format("|T%s:16|t  %s (iLvl %d)", entry.icon, entry.name, entry.level)
                GameTooltip:AddDoubleLine(leftText, L(entry.slot), 1, 1, 1, 0.7, 0.7, 0.7)
            end

            if #upgrades > 10 then
                GameTooltip:AddLine(string.format(L("  ... and %d more"), #upgrades - 10), 0.7, 0.7, 0.7)
            end
        else
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L("No better items in inventory"), 0.7, 0.7, 0.7, true)
        end

        -- Calculate minimum width based on longest item text
        local maxWidth = 250
        if #upgrades > 0 then
            local maxShow = math.min(#upgrades, 10)
            for i = 1, maxShow do
                local entry = upgrades[i]
                local textValue = string.format("%s (iLvl %d) - %s", entry.name, entry.level, L(entry.slot))
                -- Rough estimate: ~6 pixels per character + icon space
                local estimatedWidth = #textValue * 6 + 30
                if estimatedWidth > maxWidth then
                    maxWidth = estimatedWidth
                end
            end
        end
        GameTooltip:SetMinimumWidth(maxWidth)
        GameTooltip:Show()
    end)
    iLvlButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local function UpdateItemLevelDisplay()
        local avgItemLevel, avgItemLevelEquipped, avgItemLevelPvP = GetAverageItemLevel()
        local avgFormatted = format("%.2f", avgItemLevel)
        local avgEquippedFormatted = format("%.2f", avgItemLevelEquipped)

        -- Show "/ max" only when a spec-usable upgrade sits in bags and max != equipped
        -- (equal is redundant; with no usable upgrade, max reflects unequipable items).
        local betterItemsNow = GetBetterInventoryItems()
        if avgEquippedFormatted ~= avgFormatted and #betterItemsNow > 0 then
            iLvlText:SetText(format("%s / %s", avgEquippedFormatted, avgFormatted))
        else
            iLvlText:SetText(avgEquippedFormatted)
        end

        -- Stock styles: the parent panes drive visibility (see durability).
        local isCharTab = mod.CharSheetStock() or (PaperDollFrame and PaperDollFrame:IsShown())
        local showPvP = CludesUIDB and CludesUIDB.showPvpItemLevel
        local pvpVisible = false
        if showPvP and avgItemLevelPvP and avgItemLevelPvP > 0 and GetFFD(widget).pvpIlvlText then
            GetFFD(widget).pvpIlvlText:SetText(
                format("PvP iLvl: |cff00cc66%d|r", math.floor(avgItemLevelPvP))
            )
            GetFFD(widget).pvpIlvlText:SetShown(isCharTab)
            pvpVisible = isCharTab
        elseif GetFFD(widget).pvpIlvlText then
            GetFFD(widget).pvpIlvlText:Hide()
        end

        -- Re-anchor M+ Score: below PvP ilvl when visible, below iLvl when not
        if GetFFD(widget).mythicRatingLabel then
            GetFFD(widget).mythicRatingLabel:ClearAllPoints()
            local anchorFrame = pvpVisible and pvpIlvlText or iLvlText
            GetFFD(widget).mythicRatingLabel:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -4)
        end

        -- M+ Score if enabled. PaperDollFrame:IsShown() is the truth-source for the
        -- active sub-pane (selectedTab is unreliable on the initial open path).
        if CludesUIDB and CludesUIDB.showMythicRating and GetFFD(widget).mythicRatingLabel then
            local mythicRating = C_ChallengeMode.GetOverallDungeonScore()
            if mythicRating and mythicRating > 0 then
                local score = math.floor(mythicRating)
                local hex = mod.GetMPScoreHex(score)
                GetFFD(widget).mythicRatingLabel:SetText(
                    L("M+ Score:") .. string.format(" |cff%s%d|r", hex, score)
                )
                GetFFD(widget).mythicRatingLabel:SetShown(isCharTab)
            else
                GetFFD(widget).mythicRatingLabel:Hide()
            end
        elseif GetFFD(widget).mythicRatingLabel then
            GetFFD(widget).mythicRatingLabel:Hide()
        end

        if CludesUI._updateCharSheetDurability then
            CludesUI._updateCharSheetDurability()
        end
    end

    -- Event-driven refresh of the stats panel (ilvl + M+ score); zero cost when idle:
    -- inventory/spec/challenge-mode changes, registered only while the sheet is
    -- open (the OnShow pass below repaints whatever changed while it was closed).
    local iLvlUpdateFrame = CreateFrame("Frame")
    local _ILVL_EVENTS = {
        "PLAYER_EQUIPMENT_CHANGED",
        "UNIT_INVENTORY_CHANGED",
        "BAG_UPDATE",
        "PLAYER_SPECIALIZATION_CHANGED",
        "CHALLENGE_MODE_COMPLETED",
        "PLAYER_AVG_ITEM_LEVEL_UPDATE",
        -- GetItemInfo returns nil for uncached bag items; without this event such an
        -- item drops out of the better-items scan permanently (nothing else re-dirties it).
        "GET_ITEM_INFO_RECEIVED",
    }
    widget:HookScript("OnShow", function()
        for _, ev in ipairs(_ILVL_EVENTS) do
            iLvlUpdateFrame:RegisterEvent(ev)
        end
    end)
    widget:HookScript("OnHide", function()
        iLvlUpdateFrame:UnregisterAllEvents()
    end)
    -- The build runs inside the first OnShow, after that open's hooks fired.
    if widget:IsShown() then
        for _, ev in ipairs(_ILVL_EVENTS) do
            iLvlUpdateFrame:RegisterEvent(ev)
        end
    end
    local _betterItemsRefreshTimer
    local function QueueBetterItemsRefresh()
        if _betterItemsRefreshTimer then
            _betterItemsRefreshTimer:Cancel()
            _betterItemsRefreshTimer = nil
        end
        _betterItemsRefreshTimer = C_Timer.NewTimer(0.12, function()
            _betterItemsRefreshTimer = nil
            if not (widget and widget:IsShown()) then
                return
            end
            _betterDirty = true
            UpdateItemLevelDisplay()
        end)
    end
    iLvlUpdateFrame:SetScript("OnEvent", function(_, evt, unitToken)
        if evt == "UNIT_INVENTORY_CHANGED" and unitToken ~= "player" then
            return
        end
        if evt == "GET_ITEM_INFO_RECEIVED" then
            -- Gate on sheet-open BEFORE queueing: this event storms during normal play,
            -- and the cancel-and-recreate timer would still allocate every call while closed.
            if widget and widget:IsShown() then
                QueueBetterItemsRefresh()
            end
            return
        end
        if not (widget and widget:IsShown()) then
            return
        end
        _betterDirty = true
        UpdateItemLevelDisplay()
    end)
    widget:HookScript("OnShow", function()
        _betterDirty = true
        UpdateItemLevelDisplay()
    end)
    UpdateItemLevelDisplay()

    -- Store callback for option changes (M+ rating and PvP ilvl)
    CludesUI._updateMythicRatingDisplay = function()
        UpdateItemLevelDisplay()
        if CludesUI._updateScrollHeaderOffset then
            CludesUI._updateScrollHeaderOffset()
        end
    end
    CludesUI._updatePvpIlvlDisplay = CludesUI._updateMythicRatingDisplay

    -- Scroll frame starts below button+iLvl+M+ header, fills to bottom-right (right
    -- padding clears scrollbar). HEADER_H = button(25)+iLvl(18)+M+(12)+gaps(~14);
    -- the stock styles have no button row and start the iLvl 20px higher. They
    -- also sit flush in Blizzard's inset, so the rows get a left margin matching
    -- the 12px the scrollbar reserves on the right.
    local HEADER_H = mod.CharSheetStock() and 55 or 75
    local scroller = CreateFrame("ScrollFrame", "CUI_CharSheet_ScrollFrame", statsPane)
    scroller:SetPoint("TOPLEFT", statsPane, "TOPLEFT", mod.CharSheetStock() and 12 or 0, -HEADER_H)
    scroller:SetPoint("BOTTOMRIGHT", statsPane, "BOTTOMRIGHT", -12, 2)
    scroller:SetFrameLevel(statsPane:GetFrameLevel() + 1)
    GetFFD(widget).scrollFrame = scroller

    -- Scroll child: no anchors (the scroll frame positions it internally); width
    -- tracks the scroll frame whenever the panel resizes.
    local scrollChild = CreateFrame("Frame", "CUI_CharSheet_ScrollChild", scroller)
    scrollChild:SetWidth(200) -- temporary; resized by OnSizeChanged below
    scroller:SetScrollChild(scrollChild)
    scroller:HookScript("OnSizeChanged", function(self, wid)
        if wid and wid > 0 then
            scrollChild:SetWidth(wid)
        end
    end)
    -- Apply once in case OnSizeChanged doesn't fire before first paint.
    if scroller:GetWidth() and scroller:GetWidth() > 0 then
        scrollChild:SetWidth(scroller:GetWidth())
    end

    -- Custom thin scrollbar pinned to owner's right edge; thumb responds to wheel +
    -- drag. Opts: trackOwner, topInset/bottomInset, rightInset. Returns the track.
    local function AttachCustomScrollbar(scroller, scrollChild, options)
        options = options or {}
        local trackOwner = options.trackOwner or scroller
        local rightInset = options.rightInset or -2
        local topInset = options.topInset or 0
        local bottomInset = options.bottomInset or 0
        local SCROLLBAR_W, SCROLLBAR_ALPHA, SCROLL_STEP_PX, THUMB_MIN_H = 3, 0.2, 20, 20

        local track = CreateFrame("Frame", nil, trackOwner)
        track:SetWidth(SCROLLBAR_W)
        track:SetPoint("TOPRIGHT", trackOwner, "TOPRIGHT", rightInset, topInset)
        track:SetPoint("BOTTOMRIGHT", trackOwner, "BOTTOMRIGHT", rightInset, bottomInset)
        track:SetFrameLevel(scroller:GetFrameLevel() + 2)
        track:Hide()

        local knob = CreateFrame("Button", nil, track)
        knob:SetWidth(SCROLLBAR_W)
        knob:SetHeight(THUMB_MIN_H)
        knob:EnableMouse(true)
        local thumbTex = knob:CreateTexture(nil, "ARTWORK")
        thumbTex:SetColorTexture(1, 1, 1, SCROLLBAR_ALPHA)
        thumbTex:SetAllPoints()

        local function _info()
            local contentH = scrollChild:GetHeight() or 0
            local viewH = scroller:GetHeight() or 0
            return contentH, viewH, math.max(0, contentH - viewH)
        end

        local function UpdateThumb()
            local contentH, viewH, maxScroll = _info()
            if contentH <= 0 or viewH <= 0 or maxScroll <= 0 then
                track:Hide()
                return
            end
            track:Show()
            local ext = math.min(1, viewH / contentH)
            local percent = math.max(0, math.min(1, scroller:GetVerticalScroll() / maxScroll))
            local trackH = track:GetHeight()
            local thumbH = math.max(THUMB_MIN_H, trackH * ext)
            knob:SetHeight(thumbH)
            local maxTravel = math.max(0, trackH - thumbH)
            knob:ClearAllPoints()
            knob:SetPoint("TOP", track, "TOP", 0, -(percent * maxTravel))
        end
        track._update = UpdateThumb

        scroller:HookScript("OnVerticalScroll", UpdateThumb)
        scroller:HookScript("OnSizeChanged", UpdateThumb)
        scrollChild:HookScript("OnSizeChanged", UpdateThumb)

        local function refreshVerticalScroll()
            local _, _, maxScroll = _info()
            -- Unconditional on maxScroll so it still clamps after a collapse disables scrolling.
            local newScroll = math.max(0, math.min(maxScroll, scroller:GetVerticalScroll()))
            scroller:SetVerticalScroll(newScroll)
        end
        track._refreshVerticalScroll = refreshVerticalScroll

        scroller:EnableMouseWheel(true)
        scroller:SetScript("OnMouseWheel", function(_, delta)
            local _, _, maxScroll = _info()
            if maxScroll <= 0 then
                return
            end
            local newScroll =
                math.max(0, math.min(maxScroll, scroller:GetVerticalScroll() - delta * SCROLL_STEP_PX))
            scroller:SetVerticalScroll(newScroll)
        end)

        -- Drag state + handler. OnUpdate installs only during an active drag (else
        -- every visible scrollbar would run it every frame, ~120 calls/sec idle).
        local drag = { active = false, startY = 0, startScroll = 0 }
        local function _dragThumbOnUpdate(self)
            if not drag.active then
                self:SetScript("OnUpdate", nil)
                return
            end
            if not IsMouseButtonDown("LeftButton") then
                drag.active = false
                self:SetScript("OnUpdate", nil)
                return
            end
            local _, _, maxScroll = _info()
            if maxScroll <= 0 then
                return
            end
            local _, posY = GetCursorPosition()
            posY = posY / UIParent:GetEffectiveScale()
            local dy = drag.startY - posY
            local trackH = track:GetHeight()
            local maxTravel = math.max(1, trackH - knob:GetHeight())
            scroller:SetVerticalScroll(
                math.max(0, math.min(maxScroll, drag.startScroll + (dy / maxTravel) * maxScroll))
            )
        end
        knob:SetScript("OnMouseDown", function(self, btnFrame)
            if btnFrame ~= "LeftButton" then
                return
            end
            local _, posY = GetCursorPosition()
            drag.active = true
            drag.startY = posY / UIParent:GetEffectiveScale()
            drag.startScroll = scroller:GetVerticalScroll()
            self:SetScript("OnUpdate", _dragThumbOnUpdate)
        end)
        knob:SetScript("OnMouseUp", function(self, btnFrame)
            if btnFrame == "LeftButton" then
                drag.active = false
                self:SetScript("OnUpdate", nil)
            end
        end)
        -- No OnHide handler: the stock styles host the stats list under
        -- Blizzard's stats pane, whose Hide runs inside the sidebar switch
        -- (a handler there taints the Equipment Manager rows built next).
        -- The drag OnUpdate already ends itself once the button is up.

        return track
    end

    -- Stats scrollbar
    local scrollTrack = AttachCustomScrollbar(scroller, scrollChild, {
        trackOwner = statsPane,
        topInset = -HEADER_H,
    })
    GetFFD(widget).scrollBar = scrollTrack
    GetFFD(widget).updateScrollThumb = scrollTrack._update
    GetFFD(widget).refreshVerticalScroll = scrollTrack._refreshVerticalScroll

    -- Re-anchor scroll frame/track top edge to PvP iLvl + M+ Score visibility;
    -- each hidden line collapses 16px so the stat sections start higher.
    CludesUI._updateScrollHeaderOffset = function()
        local showMP = CludesUIDB and CludesUIDB.showMythicRating
        if showMP and C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore then
            local score = C_ChallengeMode.GetOverallDungeonScore()
            if not score or score <= 0 then
                showMP = false
            end
        end
        local showPvP = CludesUIDB and CludesUIDB.showPvpItemLevel
        if showPvP and GetAverageItemLevel then
            local _, _, pvp = GetAverageItemLevel()
            if not pvp or pvp <= 0 then
                showPvP = false
            end
        end
        -- HEADER_H includes M+'s line; each hidden line collapses 16px, each extra adds 16px.
        local hgt = HEADER_H
        if not showMP then
            hgt = hgt - 16
        end
        if showPvP then
            hgt = hgt + 16
        end
        local durLoc = CludesUIDB and CludesUIDB.charSheetDurabilityLocation or "model"
        if durLoc == "footer" and mod.CharSheetStock() then
            durLoc = "header"
        end
        local showDurHeader = CludesUIDB and CludesUIDB.showCharSheetDurability and durLoc == "header"
        if showDurHeader then
            hgt = hgt + 16
        end
        scroller:ClearAllPoints()
        scroller:SetPoint("TOPLEFT", statsPane, "TOPLEFT", mod.CharSheetStock() and 12 or 0, -hgt)
        scroller:SetPoint("BOTTOMRIGHT", statsPane, "BOTTOMRIGHT", -12, 2)
        scrollTrack:ClearAllPoints()
        scrollTrack:SetPoint("TOPRIGHT", statsPane, "TOPRIGHT", -2, -hgt)
        scrollTrack:SetPoint("BOTTOMRIGHT", statsPane, "BOTTOMRIGHT", -2, 0)
        if GetFFD(widget).updateScrollThumb then
            GetFFD(widget).updateScrollThumb()
        end
    end
    CludesUI._updateScrollHeaderOffset()

    local function GetCrestValue(currencyID)
        if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
            local details = C_CurrencyInfo.GetCurrencyInfo(currencyID)
            if details then
                return details.quantity or 0
            end
        end
        return 0
    end

    -- SEASON UPDATE: the crest currency ids and their caps (season 2 Mistcrests),
    -- with the Crests stat rows below. Fallback only: GetCrestMaxValue prefers
    -- the API's live seasonal max.
    local crestMaxValues = {
        [3446] = 400, -- Myth
        [3445] = 400, -- Hero
        [3444] = 700, -- Champion
        [3443] = 700, -- Veteran
        [3442] = 700, -- Adventurer
    }

    -- Crest max: prefer the API's seasonal max, fall back to the table above.
    local function GetCrestMaxValue(currencyID)
        local currency = C_CurrencyInfo.GetCurrencyInfo(currencyID)
        if currency and currency.maxQuantity then
            return currency.maxQuantity
        end
        return crestMaxValues[currencyID] or 3000
    end

    local function ShouldShowStat(statShowWhen)
        if not statShowWhen then
            return true
        end -- Show by default if no condition

        if statShowWhen == "brewmaster" then
            local specIdx = GetSpecialization()
            if specIdx then
                local specId = (GetSpecializationInfo(specIdx))
                return specId == 268 -- Brewmaster Monk
            end
            return false
        end

        return true
    end

    -- Per-crest visibility: each crest stat carries a showCrestKey, toggled
    -- individually from the options cog. Absent DB key means visible.
    local function ShouldShowCrest(statRow)
        if not statRow or not statRow.showCrestKey then
            return true
        end
        return not (CludesUIDB and CludesUIDB["showCrest_" .. statRow.showCrestKey] == false)
    end

    -- Opt-in stat rows: always created, visibility gated only, so toggles apply
    -- without /reload. Default hidden (DB flag must be explicitly true); showIf
    -- adds a live capability check on top of that choice.
    local function ShouldShowOptionalStat(statRow)
        if not statRow then
            return true
        end
        if statRow.showKey and not (CludesUIDB and CludesUIDB[statRow.showKey] == true) then
            return false
        end
        if statRow.showIf and not statRow.showIf() then
            return false
        end
        return true
    end

    -- Max mana pool. Reads 0 for classes with none (Warrior, Rogue, DK, DH), gating the Mana row -- the same check PaperDollFrame uses for alternate mana.
    local function PlayerMaxMana()
        return UnitPowerMax("player", Enum.PowerType.Mana) or 0
    end

    local function GetFilteredAttributeStats()
        local specInfo = GetSpecialization()
        local primaryStatIndex = 4 -- default Intellect

        if specInfo then
            -- Get primary stat directly from spec info (6th return value)
            local _, _, _, _, _, primaryStat = GetSpecializationInfo(specInfo)
            primaryStatIndex = primaryStat or 4
        end

        local primaryStatNames = { "Strength", "Agility", "Stamina", "Intellect" }
        local primaryStat = primaryStatNames[primaryStatIndex]

        -- Fixed order: Primary, Stamina, Health, Mana. Mana always stays in the list
        -- (row count must stay stable -- RefreshAttributeStats pairs rows to this
        -- list by index on a spec change); visibility is handled separately.
        return {
            {
                name = primaryStat,
                func = function()
                    return UnitStat("player", primaryStatIndex)
                end,
                statIndex = primaryStatIndex,
                tooltip = (primaryStatIndex == 1 and L("Increases melee attack power"))
                    or (primaryStatIndex == 2 and L("Increases dodge chance and melee attack power"))
                    or (primaryStatIndex == 4 and L("Increase the magnitude of your attacks and Abilities"))
                    or L("Primary stat"),
            },
            {
                name = "Stamina",
                func = function()
                    return UnitStat("player", 3)
                end,
                statIndex = 3,
                tooltip = L("Increases health"),
            },
            {
                name = "Health",
                func = function()
                    return UnitHealthMax("player")
                end,
                tooltip = L("The amount of damage you can take"),
            },
            {
                name = "Mana",
                func = PlayerMaxMana,
                showKey = "showManaStat",
                showIf = function()
                    return PlayerMaxMana() > 0
                end,
                tooltip = L("The size of your mana pool"),
            },
        }
    end

    -- Default category colors
    local DEFAULT_CATEGORY_COLORS = {
        Attributes = { r = 0.298, g = 0.788, b = 0.941 },
        ["Secondary Stats"] = { r = 0.471, g = 0.255, b = 0.784 },
        ["Tertiary Stats"] = { r = 0.859, g = 0.325, b = 0.855 },
        Attack = { r = 1, g = 0.353, b = 0.122 },
        Defense = { r = 0.247, g = 0.655, b = 1 },
        Crests = { r = 1, g = 0.784, b = 0.341 },
        PvP = { r = 0.671, g = 0.431, b = 0.349 },
    }

    local function GetCategoryColor(titleText)
        local blizz = mod.CharSheetBlizzColor()
        if blizz then
            return blizz
        end
        local useCustom = CludesUIDB
            and CludesUIDB.statCategoryUseColor
            and CludesUIDB.statCategoryUseColor[titleText]
        if useCustom then
            local custom = CludesUIDB
                and CludesUIDB.statCategoryColors
                and CludesUIDB.statCategoryColors[titleText]
            if custom then
                return custom
            end
        end
        return DEFAULT_CATEGORY_COLORS[titleText] or { r = 1, g = 1, b = 1 }
    end

    local function GetStatSectionsOrder()
        local defaultOrder = {
            {
                title = "Attributes",
                colorKey = "Attributes",
                color = GetCategoryColor("Attributes"),
                stats = GetFilteredAttributeStats(),
            },
            {
                title = "Secondary",
                colorKey = "Secondary Stats",
                settingKey = "SecondaryStats",
                color = GetCategoryColor("Secondary Stats"),
                stats = {
                    {
                        name = "Critical Strike",
                        func = function()
                            return (CludesUI.PlayerCritChance())
                        end,
                        format = "%.2f%%",
                        rawFunc = function()
                            local _, critCR = CludesUI.PlayerCritChance()
                            return GetCombatRating(critCR) or 0
                        end,
                    },
                    {
                        name = "Haste",
                        func = function()
                            return UnitSpellHaste("player") or 0
                        end,
                        format = "%.2f%%",
                        rawFunc = function()
                            return GetCombatRating(CR_HASTE_MELEE) or 0
                        end,
                    },
                    {
                        name = "Mastery",
                        func = function()
                            return GetMasteryEffect() or 0
                        end,
                        format = "%.2f%%",
                        rawFunc = function()
                            return GetCombatRating(CR_MASTERY) or 0
                        end,
                    },
                    {
                        name = "Versatility",
                        func = function()
                            local rating = GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE) or 0
                            local base = GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE) or 0
                            if issecretvalue(rating) or issecretvalue(base) then
                                return rating
                            end
                            return rating + base
                        end,
                        format = "%.2f%%",
                        rawFunc = function()
                            return GetCombatRating(CR_VERSATILITY_DAMAGE_DONE) or 0
                        end,
                    },
                },
            },
            {
                title = "Tertiary",
                colorKey = "Tertiary Stats",
                settingKey = "Tertiary",
                color = GetCategoryColor("Tertiary Stats"),
                stats = {
                    -- GetLifesteal/GetAvoidance/GetSpeed return TOTAL percent (incl.
                    -- talent/racial bonuses); GetCombatRatingBonus is rating-only and
                    -- misses e.g. Shadow Priest's +2% innate leech talent.
                    {
                        name = "Leech",
                        func = function()
                            return GetLifesteal() or 0
                        end,
                        format = "%.2f%%",
                        rawFunc = function()
                            return GetCombatRating(CR_LIFESTEAL) or 0
                        end,
                    },
                    {
                        name = "Avoidance",
                        func = function()
                            return GetAvoidance() or 0
                        end,
                        format = "%.2f%%",
                        rawFunc = function()
                            return GetCombatRating(CR_AVOIDANCE) or 0
                        end,
                    },
                    {
                        name = "Speed",
                        func = function()
                            return GetSpeed() or 0
                        end,
                        format = "%.2f%%",
                        rawFunc = function()
                            return GetCombatRating(CR_SPEED) or 0
                        end,
                    },
                },
            },
            {
                title = "Attack",
                colorKey = "Attack",
                color = GetCategoryColor("Attack"),
                stats = {
                    {
                        name = "Spell Power",
                        func = function()
                            return GetSpellBonusDamage(7)
                        end,
                        tooltip = L("Increases the power of your spells and abilities"),
                    },
                    {
                        name = "Attack Speed",
                        func = function()
                            return UnitAttackSpeed("player") or 0
                        end,
                        format = "%.2f",
                        tooltip = L("Attacks per second"),
                    },
                },
            },
            {
                title = "Defense",
                colorKey = "Defense",
                color = GetCategoryColor("Defense"),
                stats = {
                    {
                        name = "Armor",
                        func = function()
                            local base, effectiveArmor = UnitArmor("player")
                            return effectiveArmor
                        end,
                        tooltip = L("Reduces physical damage taken"),
                    },
                    {
                        name = "Dodge",
                        func = function()
                            return GetDodgeChance() or 0
                        end,
                        format = "%.2f%%",
                        tooltip = L("Chance to avoid melee attacks"),
                    },
                    {
                        name = "Parry",
                        func = function()
                            return GetParryChance() or 0
                        end,
                        format = "%.2f%%",
                        tooltip = L("Chance to deflect melee attacks"),
                    },
                    {
                        name = "Block",
                        func = function()
                            return GetBlockChance() or 0
                        end,
                        format = "%.2f%%",
                        tooltip = L("Chance to block incoming attacks with a shield"),
                    },
                    {
                        name = "Stagger Effect",
                        func = function()
                            return C_PaperDollInfo.GetStaggerPercentage("player") or 0
                        end,
                        format = "%.2f%%",
                        showWhen = "brewmaster",
                        tooltip = L("Converts damage into a delayed effect"),
                    },
                },
            },
            {
                title = "Crests",
                colorKey = "Crests",
                color = GetCategoryColor("Crests"),
                -- SEASON UPDATE: the season's crest currency ids, highest tier first.
                stats = {
                    {
                        name = "Myth",
                        showCrestKey = "Myth",
                        func = function()
                            return GetCrestValue(3446)
                        end,
                        format = "%d",
                        currencyID = 3446,
                    },
                    {
                        name = "Hero",
                        showCrestKey = "Hero",
                        func = function()
                            return GetCrestValue(3445)
                        end,
                        format = "%d",
                        currencyID = 3445,
                    },
                    {
                        name = "Champion",
                        showCrestKey = "Champion",
                        func = function()
                            return GetCrestValue(3444)
                        end,
                        format = "%d",
                        currencyID = 3444,
                    },
                    {
                        name = "Veteran",
                        showCrestKey = "Veteran",
                        func = function()
                            return GetCrestValue(3443)
                        end,
                        format = "%d",
                        currencyID = 3443,
                    },
                    {
                        name = "Adventurer",
                        showCrestKey = "Adventurer",
                        func = function()
                            return GetCrestValue(3442)
                        end,
                        format = "%d",
                        currencyID = 3442,
                    },
                },
            },
            {
                title = "PvP",
                colorKey = "PvP",
                settingKey = "PvP",
                color = GetCategoryColor("PvP"),
                stats = {
                    {
                        name = "Honor Level",
                        format = "%s",
                        func = function()
                            return tostring(UnitHonorLevel and UnitHonorLevel("player") or 0)
                        end,
                    },
                    {
                        name = "Honor",
                        format = "%s",
                        func = function()
                            local current = (UnitHonor and UnitHonor("player")) or 0
                            local max = (UnitHonorMax and UnitHonorMax("player")) or 0
                            return BreakUpLargeNumbers(current) .. "/" .. BreakUpLargeNumbers(max)
                        end,
                    },
                    {
                        name = "Conquest",
                        format = "%d",
                        currencyID = 1602,
                        func = function()
                            if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
                                local details = C_CurrencyInfo.GetCurrencyInfo(1602)
                                return (details and details.quantity) or 0
                            end
                            return 0
                        end,
                    },
                },
            },
        }

        if CludesUIDB and CludesUIDB.statSectionsOrder then
            local orderedSections = {}
            for _, titleText in ipairs(CludesUIDB.statSectionsOrder) do
                for _, sectionRec in ipairs(defaultOrder) do
                    if sectionRec.title == titleText then
                        table.insert(orderedSections, sectionRec)
                        break
                    end
                end
            end
            return #orderedSections == #defaultOrder and orderedSections or defaultOrder
        end
        return defaultOrder
    end

    -- Stat hover highlight (opt-in per category): the equipped slots whose item
    -- stats grant the hovered stat glow, in the socket panel's slot-spotlight
    -- style. Keys are the ITEM_MOD_* tokens C_Item.GetItemStats returns
    -- (locale-independent; the socket panel's GetGemStatText reads the same
    -- ones). One glow frame per slot, built on first use and reused.
    local STAT_NAME_TO_ITEM_MOD = {
        -- Secondary stats
        ["Critical Strike"] = "ITEM_MOD_CRIT_RATING_SHORT",
        ["Haste"] = "ITEM_MOD_HASTE_RATING_SHORT",
        ["Mastery"] = "ITEM_MOD_MASTERY_RATING_SHORT",
        ["Versatility"] = "ITEM_MOD_VERSATILITY",
        -- Tertiary stats
        ["Leech"] = "ITEM_MOD_CR_LIFESTEAL_SHORT",
        ["Avoidance"] = "ITEM_MOD_CR_AVOIDANCE_SHORT",
        ["Speed"] = "ITEM_MOD_CR_SPEED_SHORT",
    }
    local statGlows, statGlowsLit = {}, false
    local function StopStatHighlights()
        if not statGlowsLit then
            return
        end
        statGlowsLit = false
        for _, frame in pairs(statGlows) do
            if frame:IsShown() then
                CludesUI.Glows.StopGlow(frame)
                frame:Hide()
            end
        end
    end
    local function StartStatHighlights(statName)
        StopStatHighlights()
        local modKey = STAT_NAME_TO_ITEM_MOD[statName]
        if not modKey then
            return
        end
        for _, slotKey in ipairs(CUI_GEAR_SLOTS) do
            local slotFrame = _G[slotKey]
            local slotID = slotFrame and slotFrame:GetID()
            local link = slotID and GetInventoryItemLink("player", slotID)
            local stats = link and C_Item.GetItemStats(link)
            local val = stats and stats[modKey]
            if type(val) == "number" and val > 0 then
                local frame = statGlows[slotID]
                if not frame then
                    frame = CreateFrame("Frame", nil, CharacterFrame)
                    frame:SetAllPoints(slotFrame)
                    statGlows[slotID] = frame
                end
                frame:SetFrameStrata(slotFrame:GetFrameStrata())
                frame:SetFrameLevel(slotFrame:GetFrameLevel() + 5)
                frame:Show()
                local wid, hgt = slotFrame:GetWidth(), slotFrame:GetHeight()
                if not wid or wid < 1 then
                    wid = 37
                end
                if not hgt or hgt < 1 then
                    hgt = wid
                end
                CludesUI.Glows.StartGlow(frame, 6, wid, 1, 1, 1, nil, hgt)
                statGlowsLit = true
            end
        end
    end

    local statSections = GetStatSectionsOrder()

    GetFFD(widget).statsPanel = statsPane
    GetFFD(widget).statsValues = {} -- Will be filled as sections are created
    GetFFD(widget).statsSections = {} -- Store sections for collapse/expand
    GetFFD(widget).lastSpec = GetSpecialization() -- Track current spec

    -- Rebuild the Attributes rows when the spec changed.
    local function RefreshAttributeStats()
        local currentSpec = GetSpecialization()
        if currentSpec == GetFFD(widget).lastSpec then
            return
        end

        GetFFD(widget).lastSpec = currentSpec

        for sectionIdx, sectionInfo in ipairs(GetFFD(widget).statsSections) do
            if sectionInfo.sectionTitle == "Attributes" then
                local newStats = GetFilteredAttributeStats()

                local labelIdx = 0
                for _, statRow in ipairs(sectionInfo.stats) do
                    if statRow.label then
                        labelIdx = labelIdx + 1

                        if newStats[labelIdx] then
                            -- Shown state respects the section's collapsed flag: a spec switch
                            -- refreshes row data while collapsed but must not force it visible.
                            statRow.label:SetText(L(newStats[labelIdx].name))
                            statRow.label:SetShown(not sectionInfo.isCollapsed)

                            if statRow.value then
                                for _, statsValueEntry in ipairs(GetFFD(widget).statsValues) do
                                    if statsValueEntry.value == statRow.value then
                                        statsValueEntry.func = newStats[labelIdx].func
                                        statsValueEntry.format = newStats[labelIdx].format or "%d"
                                        local newValue = newStats[labelIdx].func()
                                        if newValue ~= nil then
                                            local formatStr = statsValueEntry.format
                                            if formatStr:find("%%") then
                                                statRow.value:SetText(format(formatStr, newValue))
                                            else
                                                statRow.value:SetText(format(formatStr, newValue))
                                            end
                                        end
                                        break
                                    end
                                end
                                statRow.value:SetShown(not sectionInfo.isCollapsed)
                            end
                        else
                            statRow.label:Hide()
                            if statRow.value then
                                statRow.value:Hide()
                            end
                        end
                    elseif statRow.divider then
                        -- Show dividers only between visible stats, and only when the section isn't collapsed.
                        statRow.divider:SetShown(not sectionInfo.isCollapsed and labelIdx < #newStats)
                    end
                end

                GetFFD(widget).recalculateSections()
                break
            end
        end
    end

    -- Refresh row visibility against the showWhen / crest / opt-in filters.
    local function RefreshStatsVisibility()
        local currentSpec = GetSpecialization()

        for _, sectionInfo in ipairs(GetFFD(widget).statsSections) do
            -- Collapsed sections keep all rows hidden regardless of per-stat filters (collapse/expand owns visibility).
            if not sectionInfo.isCollapsed then
                local visibleCount = 0
                for si = 1, #sectionInfo.stats do
                    local statRow = sectionInfo.stats[si]
                    if statRow.label and (statRow.showWhen or statRow.showCrestKey or statRow.showKey) then
                        local shouldShow = ShouldShowStat(statRow.showWhen)
                            and ShouldShowCrest(statRow)
                            and ShouldShowOptionalStat(statRow)
                        statRow.label:SetShown(shouldShow)
                        if statRow.value then
                            statRow.value:SetShown(shouldShow)
                        end
                        if statRow.button then
                            statRow.button:SetShown(shouldShow)
                        end
                        -- Hide/show the divider that follows this stat
                        local nextEntry = sectionInfo.stats[si + 1]
                        if nextEntry and nextEntry.divider then
                            nextEntry.divider:SetShown(shouldShow)
                        end
                        if shouldShow then
                            visibleCount = visibleCount + 1
                        end
                    elseif statRow.label then
                        visibleCount = visibleCount + 1
                    end
                end
                -- Recalculate section height based on visible stats
                sectionInfo.height = 22 + (visibleCount * 16)
            end
        end
        GetFFD(widget).recalculateSections()
        -- A row just re-shown was skipped by the last UpdateAllStats pass, so its value
        -- is stale/unset; repopulate here (toggle/spec/collapse paths only, never the
        -- event path). Guarded since the build calls this before UpdateAllStats is
        -- published, but the build's own pass covers that case.
        if CludesUI._refreshStatFormats then
            CludesUI._refreshStatFormats()
        end
    end
    CludesUI._refreshStatsVisibility = RefreshStatsVisibility

    -- Event-driven primary-stat + stat-visibility refresh. Fires only on spec
    -- / talent changes and once on panel open: no row filter reads stats,
    -- ratings or gear (those repaint values only, through the stat-value set
    -- below), so the storming events never take this re-layout path.
    local specUpdateFrame = CreateFrame("Frame")
    local _SPEC_EVENTS = {
        "PLAYER_SPECIALIZATION_CHANGED",
        "ACTIVE_TALENT_GROUP_CHANGED",
    }
    specUpdateFrame:SetScript("OnEvent", function()
        -- Coalesced with the stat-value events into one flush per frame (the
        -- queue is published below, once UpdateAllStats exists).
        local queue = GetFFD(widget).queueStats
        if queue then
            queue(true)
            return
        end
        RefreshAttributeStats()
        RefreshStatsVisibility()
    end)
    -- Same dynamic-registration trick as statsEventFrame below.
    widget:HookScript("OnShow", function()
        for _, ev in ipairs(_SPEC_EVENTS) do
            specUpdateFrame:RegisterEvent(ev)
        end
    end)
    widget:HookScript("OnHide", function()
        specUpdateFrame:UnregisterAllEvents()
        -- A close mid-hover never fires the stat row's OnLeave
        StopStatHighlights()
    end)
    -- The build runs inside the first OnShow, after that open's hooks fired.
    if widget:IsShown() then
        for _, ev in ipairs(_SPEC_EVENTS) do
            specUpdateFrame:RegisterEvent(ev)
        end
    end
    widget:HookScript("OnShow", function()
        RefreshAttributeStats()
        RefreshStatsVisibility()
        if CludesUI._updateStatCategoryVisibility then
            CludesUI._updateStatCategoryVisibility()
        end
        -- Deferred re-layout: scroll child bounds may not be finalized on the OnShow
        -- frame, causing sections to stack on first open.
        C_Timer.After(0, function()
            RefreshStatsVisibility()
            if CludesUI._updateStatCategoryVisibility then
                CludesUI._updateStatCategoryVisibility()
            end
        end)
    end)

    -- Show/hide whole stat categories per their DB setting.
    local function UpdateStatCategoryVisibility()
        if not GetFFD(widget).statsSections or #GetFFD(widget).statsSections == 0 then
            return
        end

        for _, sectionInfo in ipairs(GetFFD(widget).statsSections) do
            local settingKey = "showStatCategory_"
                .. (sectionInfo.settingKey or sectionInfo.sectionTitle:gsub(" ", ""))
            local shouldShow = not (CludesUIDB and CludesUIDB[settingKey] == false)

            if shouldShow then
                sectionInfo.container:Show()
            else
                sectionInfo.container:Hide()
                sectionInfo.container:ClearAllPoints()
                sectionInfo.container:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 10000)
            end
        end
        GetFFD(widget).recalculateSections()
    end
    CludesUI._updateStatCategoryVisibility = UpdateStatCategoryVisibility

    local function RecalculateSectionPositions()
        -- Collect visible sections so first/last are known once hidden ones are out
        local visible = {}
        for _, sectionInfo in ipairs(GetFFD(widget).statsSections) do
            if sectionInfo.container:IsShown() then
                visible[#visible + 1] = sectionInfo
            end
        end

        local offY = 0
        for position, sectionInfo in ipairs(visible) do
            local sectionHeight = sectionInfo.isCollapsed and 16 or sectionInfo.height
            sectionInfo.container:ClearAllPoints()
            sectionInfo.container:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, offY)
            sectionInfo.container:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, offY)
            sectionInfo.container:SetHeight(sectionHeight)
            offY = offY - sectionHeight - 6

            -- Gray out first-up and last-down; restore hover scripts on enabled arrows
            local upButton, downButton = sectionInfo.upBtn, sectionInfo.downBtn
            local alpha = sectionInfo._arrowAlpha or 0.35
            local hover = sectionInfo._arrowHover or 1
            if upButton then
                if position == 1 then
                    upButton:SetAlpha(0.25)
                    upButton:SetScript("OnEnter", nil)
                    upButton:SetScript("OnLeave", nil)
                    upButton:EnableMouse(false)
                else
                    upButton:SetAlpha(alpha)
                    upButton:EnableMouse(true)
                    upButton:SetScript("OnEnter", function(self)
                        self:SetAlpha(hover)
                    end)
                    upButton:SetScript("OnLeave", function(self)
                        self:SetAlpha(alpha)
                    end)
                end
            end
            if downButton then
                if position == #visible then
                    downButton:SetAlpha(0.25)
                    downButton:SetScript("OnEnter", nil)
                    downButton:SetScript("OnLeave", nil)
                    downButton:EnableMouse(false)
                else
                    downButton:SetAlpha(alpha)
                    downButton:EnableMouse(true)
                    downButton:SetScript("OnEnter", function(self)
                        self:SetAlpha(hover)
                    end)
                    downButton:SetScript("OnLeave", function(self)
                        self:SetAlpha(alpha)
                    end)
                end
            end
        end
        scrollChild:SetHeight(-offY)
        if GetFFD(widget).refreshVerticalScroll then
            GetFFD(widget).refreshVerticalScroll()
        end
    end
    GetFFD(widget).recalculateSections = RecalculateSectionPositions

    -- Create sections in scroll child
    local offY = 0
    for sectionIdx, sectionRec in ipairs(statSections) do
        local sectionHolder = CreateFrame("Frame", nil, scrollChild)
        sectionHolder:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, offY)
        sectionHolder:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, offY)
        sectionHolder:SetWidth(260)

        -- Title + bar container spans the full section width so the left bar starts
        -- flush with stat labels and the right bar ends flush with stat values.
        local titleHolder = CreateFrame("Button", nil, sectionHolder)
        titleHolder:SetPoint("TOPLEFT", sectionHolder, "TOPLEFT", 0, 0)
        titleHolder:SetPoint("TOPRIGHT", sectionHolder, "TOPRIGHT", 0, 0)
        titleHolder:SetHeight(16)
        titleHolder:RegisterForClicks("LeftButtonUp")

        local sectionTitle = titleHolder:CreateFontString(nil, "OVERLAY")
        sectionTitle:SetFont(fontFile, 11, "")
        sectionTitle:SetTextColor(sectionRec.color.r, sectionRec.color.g, sectionRec.color.b, 1)
        sectionTitle:SetPoint("CENTER", titleHolder, "CENTER", 0, 0)
        sectionTitle:SetText(L(sectionRec.title))

        -- Physical-pixel-perfect 1px dividers, same technique as PP.CreateBorder:
        -- disable engine snap, height = one physical pixel in effective-scale units.
        local PP_SEC = CludesUI and CludesUI.PanelPP
        local PP_CORE = CludesUI and CludesUI.PP
        local function _snapSecLine(texture)
            if PP_SEC and PP_SEC.DisablePixelSnap then
                PP_SEC.DisablePixelSnap(texture)
            end
            local perfect = (PP_CORE and PP_CORE.perfect) or (PP_SEC and PP_SEC.mult) or 1
            local es = titleHolder.GetEffectiveScale and titleHolder:GetEffectiveScale() or 1
            local onePixel = (es and es > 0) and (perfect / es) or (PP_SEC and PP_SEC.mult) or 1
            texture:SetHeight(onePixel)
        end

        local leftStrip = titleHolder:CreateTexture(nil, "ARTWORK")
        leftStrip:SetColorTexture(sectionRec.color.r, sectionRec.color.g, sectionRec.color.b, 0.8)
        leftStrip:SetPoint("LEFT", titleHolder, "LEFT", 0, 0)
        leftStrip:SetPoint("RIGHT", sectionTitle, "LEFT", -6, 0)
        _snapSecLine(leftStrip)

        local rightStrip = titleHolder:CreateTexture(nil, "ARTWORK")
        rightStrip:SetColorTexture(sectionRec.color.r, sectionRec.color.g, sectionRec.color.b, 0.8)
        rightStrip:SetPoint("LEFT", sectionTitle, "RIGHT", 6, 0)
        rightStrip:SetPoint("RIGHT", titleHolder, "RIGHT", 0, 0)
        _snapSecLine(rightStrip)

        -- Re-snap once after layout settles: GetEffectiveScale needs final parent
        -- positions, not ready on first build.
        titleHolder._barResnap = { leftStrip, rightStrip }
        local _ticks = 0
        titleHolder:SetScript("OnUpdate", function(self)
            _ticks = _ticks + 1
            _snapSecLine(leftStrip)
            _snapSecLine(rightStrip)
            if _ticks >= 2 then
                self:SetScript("OnUpdate", nil)
            end
        end)

        local statYOffset = -22

        -- Section data for collapse/expand. Collapsed state persists across sessions
        -- in CludesUIDB.charSheetCollapsedSections, keyed by settingKey.
        local _collapseKey = sectionRec.settingKey or sectionRec.title:gsub(" ", "")
        local _savedCollapsed = false
        if CludesUIDB and CludesUIDB.charSheetCollapsedSections then
            _savedCollapsed = CludesUIDB.charSheetCollapsedSections[_collapseKey] == true
        end
        local sectionInfo = {
            title = titleHolder,
            container = sectionHolder,
            stats = {},
            isCollapsed = _savedCollapsed,
            height = 0,
            sectionTitle = sectionRec.title, -- display name (used for reordering)
            -- Stable SavedVariables key; falls back to the title, spaces stripped.
            settingKey = sectionRec.settingKey or sectionRec.title:gsub(" ", ""),
            colorKey = sectionRec.colorKey or sectionRec.title, -- DB key for custom color
            titleFS = sectionTitle,
            leftBar = leftStrip,
            rightBar = rightStrip,
        }
        table.insert(GetFFD(widget).statsSections, sectionInfo)

        -- Stats in section
        for statIdx, statRow in ipairs(sectionRec.stats) do
            if ShouldShowStat(statRow.showWhen) and ShouldShowCrest(statRow) then
                local caption = sectionHolder:CreateFontString(nil, "OVERLAY")
                caption:SetFont(fontFile, 10, "")
                caption:SetTextColor(0.7, 0.7, 0.7, 0.8)
                caption:SetPoint("TOPLEFT", sectionHolder, "TOPLEFT", 0, statYOffset)
                caption:SetText(L(statRow.name))

                local amount = sectionHolder:CreateFontString(nil, "OVERLAY")
                amount:SetFont(fontFile, 10, "")
                -- "Blizzard UI Color" colours only the titles; values take the label grey.
                if mod.CharSheetBlizzColor() then
                    amount:SetTextColor(0.7, 0.7, 0.7, 0.8)
                else
                    amount:SetTextColor(sectionRec.color.r, sectionRec.color.g, sectionRec.color.b, 1)
                end
                amount:SetPoint("TOPRIGHT", sectionHolder, "TOPRIGHT", 0, statYOffset)
                amount:SetJustifyH("RIGHT")
                amount:SetText("0")

                -- Tooltip overlay button spanning the full row width (label edge to
                -- value edge) so hovering anywhere on the line fires it.
                local valueButton = CreateFrame("Button", nil, sectionHolder)
                valueButton:SetPoint("TOPLEFT", sectionHolder, "TOPLEFT", 0, statYOffset)
                valueButton:SetPoint("TOPRIGHT", sectionHolder, "TOPRIGHT", 0, statYOffset)
                valueButton:SetHeight(16)
                valueButton:EnableMouse(true)

                valueButton:SetScript("OnEnter", function()
                    local specIdx = GetSpecialization and GetSpecialization()
                    local role = specIdx and GetSpecializationRole(specIdx) or nil

                    local statValue = statRow.func()
                    if issecretvalue(statValue) then
                        return
                    end
                    GameTooltip:SetOwner(valueButton, "ANCHOR_RIGHT")

                    -- Read the title's CURRENT color (section.color is build-time and
                    -- stays stale until /reload; the title FontString is live-updated
                    -- by CludesUI._refreshCharacterSheetColors) so a swatch change matches instantly.
                    local scR, scG, scB = sectionTitle:GetTextColor()

                    local displayValue = statValue
                    if statRow.format then
                        displayValue = string.format(statRow.format, statValue)
                    else
                        displayValue = tostring(statValue)
                    end

                    local titleLine = L(statRow.name) .. " " .. displayValue

                    -- Currency (Crests)
                    if statRow.currencyID then
                        local currency = C_CurrencyInfo.GetCurrencyInfo(statRow.currencyID)
                        if currency then
                            local earned = currency.totalEarned or 0
                            local maximum = currency.maxQuantity or 0
                            GameTooltip:AddLine(L(statRow.name) .. L(" Crests"), scR, scG, scB, 1)
                            GameTooltip:AddLine(string.format("%d / %d", earned, maximum), 1, 1, 1, true)
                        end
                    -- Secondary stats with raw rating
                    elseif statRow.rawFunc then
                        local percentValue = statRow.func()
                        local rawValue = statRow.rawFunc()
                        GameTooltip:AddLine(
                            string.format(L("%s %.2f%% (%d rating)"), L(statRow.name), percentValue, rawValue),
                            scR,
                            scG,
                            scB,
                            true -- category color (live)
                        )
                        local description = ""
                        if statRow.name == "Critical Strike" then
                            description = string.format(
                                L("Increases your chance to critically hit by %.2f%%."),
                                percentValue
                            )
                        elseif statRow.name == "Haste" then
                            description = string.format(
                                L("Increases attack and casting speed by %.2f%%."),
                                percentValue
                            )
                        elseif statRow.name == "Mastery" then
                            -- Pull the spec's real mastery spell description instead of a generic line.
                            if
                                specIdx
                                and GetSpecializationMasterySpells
                                and C_Spell
                                and C_Spell.GetSpellDescription
                            then
                                local masterySpell, masterySpell2 = GetSpecializationMasterySpells(specIdx)
                                if masterySpell then
                                    description = C_Spell.GetSpellDescription(masterySpell) or ""
                                    if masterySpell2 then
                                        local d2 = C_Spell.GetSpellDescription(masterySpell2)
                                        if d2 and d2 ~= "" then
                                            description = description .. "\n" .. d2
                                        end
                                    end
                                end
                            end
                            if description == "" then
                                description = string.format(
                                    L("Increases the effectiveness of your Mastery by %.2f%%."),
                                    percentValue
                                )
                            end
                        elseif statRow.name == "Versatility" then
                            description = string.format(
                                L(
                                    "Increases damage and healing done by %.2f%% and reduces damage taken by %.2f%%."
                                ),
                                percentValue,
                                percentValue / 2
                            )
                        elseif statRow.name == "Leech" then
                            description =
                                string.format(L("Heals for %.2f%% of damage and healing done."), percentValue)
                        elseif statRow.name == "Avoidance" then
                            description = string.format(
                                L("Reduces damage taken from area attacks by %.2f%%."),
                                percentValue
                            )
                        elseif statRow.name == "Speed" then
                            description =
                                string.format(L("Increases movement speed by %.2f%%."), percentValue)
                        end
                        GameTooltip:AddLine(description, 1, 1, 1, true)

                        if statRow.name == "Critical Strike" and GetCritChanceProvidesParryEffect() then
                            local _, critCR = CludesUI.PlayerCritChance()
                            local critToParry =
                                GetCombatRatingBonusForCombatRatingValue(CR_PARRY, GetCombatRating(critCR))
                            GameTooltip:AddLine(" ")
                            GameTooltip:AddLine(
                                string.format(L("Increases parry chance by %.2f%%."), critToParry),
                                1,
                                1,
                                1,
                                true
                            )
                        end

                        -- Diminishing returns breakdown (opt-in via Stat Display)
                        if
                            CludesUIDB
                            and CludesUIDB.showAdjustedStats
                            and not issecretvalue(rawValue)
                            and CludesUI.GetStatDR
                        then
                            local adjusted, wasted, penalty, nextPenalty, nextThreshold =
                                CludesUI.GetStatDR(statRow.name, rawValue)
                            if adjusted then
                                GameTooltip:AddLine(" ")
                                GameTooltip:AddLine(
                                    string.format(
                                        L("Adjusted Rating: %s"),
                                        BreakUpLargeNumbers(math.floor(adjusted + 0.5))
                                    ),
                                    scR,
                                    scG,
                                    scB,
                                    true
                                )
                                GameTooltip:AddLine(
                                    string.format(
                                        L("Wasted Rating: %s"),
                                        BreakUpLargeNumbers(math.floor(wasted + 0.5))
                                    ),
                                    scR,
                                    scG,
                                    scB,
                                    true
                                )
                                GameTooltip:AddLine(
                                    string.format(L("Penalty Percentage: %d%%"), penalty),
                                    scR,
                                    scG,
                                    scB,
                                    true
                                )
                                if nextThreshold then
                                    local nextRating = math.floor(nextThreshold + 0.5)
                                    local needed = nextRating - math.floor(rawValue + 0.5)
                                    if needed < 0 then
                                        needed = 0
                                    end
                                    GameTooltip:AddLine(
                                        string.format(
                                            L("Next %d%% Penalty At: %s (+%s)"),
                                            nextPenalty,
                                            BreakUpLargeNumbers(nextRating),
                                            BreakUpLargeNumbers(needed)
                                        ),
                                        scR,
                                        scG,
                                        scB,
                                        true
                                    )
                                end
                            end
                        end
                    -- Attributes
                    elseif statRow.statIndex then
                        local base, _, posBuff, negBuff = UnitStat("player", statRow.statIndex)
                        -- base from UnitStat is wrong, so calculate it like the default UI does
                        base = base - posBuff - negBuff
                        local statCaption = statRow.name

                        -- Map to Blizzard global names
                        if statRow.name == "Strength" then
                            statCaption = STAT_STRENGTH or L("Strength")
                        elseif statRow.name == "Agility" then
                            statCaption = STAT_AGILITY or L("Agility")
                        elseif statRow.name == "Intellect" then
                            statCaption = STAT_INTELLECT or L("Intellect")
                        elseif statRow.name == "Stamina" then
                            statCaption = STAT_STAMINA or L("Stamina")
                        end

                        local bonus = (posBuff or 0) + (negBuff or 0)
                        local statLine = statCaption .. " " .. statValue
                        if bonus ~= 0 then
                            statLine = statLine .. " (" .. base .. (bonus > 0 and "+" or "") .. bonus .. ")"
                        end
                        GameTooltip:AddLine(statLine, scR, scG, scB, true)
                        GameTooltip:AddLine(L(statRow.tooltip), 1, 1, 1, true)

                        -- Tanks: extra line for Strength (parry) / Agility (dodge).
                        if role == "TANK" then
                            if statRow.name == "Strength" then
                                if GetParryChanceFromAttribute then
                                    local parryFromStr = GetParryChanceFromAttribute()

                                    if parryFromStr and parryFromStr > 0 then
                                        GameTooltip:AddLine(" ")
                                        GameTooltip:AddLine(
                                            string.format(
                                                L("Increases parry chance by %.2f%%."),
                                                parryFromStr
                                            ),
                                            1,
                                            1,
                                            1,
                                            true
                                        )
                                        GameTooltip:AddLine(
                                            L("|cff888888(Before diminishing returns)|r"),
                                            1,
                                            1,
                                            1,
                                            true
                                        )
                                    end
                                end
                            elseif statRow.name == "Agility" then
                                if GetDodgeChanceFromAttribute then
                                    local dodgeChanceStr = GetDodgeChanceFromAttribute()

                                    if dodgeChanceStr and dodgeChanceStr > 0 then
                                        GameTooltip:AddLine(" ")
                                        GameTooltip:AddLine(
                                            string.format(
                                                L("Increases dodge chance by %.2f%%."),
                                                dodgeChanceStr
                                            ),
                                            1,
                                            1,
                                            1,
                                            true
                                        )
                                        GameTooltip:AddLine(
                                            L("|cff888888(Before diminishing returns)|r"),
                                            1,
                                            1,
                                            1,
                                            true
                                        )
                                    end
                                end
                            end
                        end
                    -- Generic stats (Attack, Defense, etc.)
                    else
                        GameTooltip:AddLine(titleLine, scR, scG, scB, true)
                        if statRow.tooltip then
                            GameTooltip:AddLine(L(statRow.tooltip), 1, 1, 1, true)
                        end

                        if statRow.name == "Armor" then
                            local _, effectiveArmor = UnitArmor("player")
                            local armorReduction = 0

                            -- Reduction against an evenly matched enemy
                            if C_PaperDollInfo and C_PaperDollInfo.GetArmorEffectiveness then
                                armorReduction = (
                                    C_PaperDollInfo.GetArmorEffectiveness(effectiveArmor, UnitLevel("player"))
                                    or 0
                                ) * 100
                            end
                            if armorReduction > 0 then
                                GameTooltip:AddLine(" ")
                                GameTooltip:AddLine(
                                    string.format(L("Physical damage reduction: %.2f%%"), armorReduction),
                                    1,
                                    1,
                                    1,
                                    true
                                )
                                GameTooltip:AddLine(
                                    L("|cff888888(Against an evenly matched enemy)|r"),
                                    1,
                                    1,
                                    1,
                                    true
                                )
                            end

                            -- Reduction against target: return can be SECRET when target combat
                            -- data is secret; issecretvalue-guard before any compare (comparing throws).
                            if C_PaperDollInfo and C_PaperDollInfo.GetArmorEffectivenessAgainstTarget then
                                local targetEff =
                                    C_PaperDollInfo.GetArmorEffectivenessAgainstTarget(effectiveArmor)
                                if targetEff and not issecretvalue(targetEff) and targetEff > 0 then
                                    GameTooltip:AddLine(
                                        string.format(L("(Against Current Target: %.2f%%)"), targetEff * 100),
                                        1,
                                        1,
                                        1,
                                        true
                                    )
                                end
                            end
                        elseif statRow.name == "Block" then
                            local shieldBlockArmor = GetShieldBlock()
                            local armorReduction = 0

                            -- Reduction against an evenly matched enemy
                            if C_PaperDollInfo and C_PaperDollInfo.GetArmorEffectiveness then
                                armorReduction = (
                                    C_PaperDollInfo.GetArmorEffectiveness(
                                        shieldBlockArmor,
                                        UnitLevel("player")
                                    ) or 0
                                ) * 100
                            end
                            if armorReduction > 0 then
                                GameTooltip:AddLine(" ")
                                GameTooltip:AddLine(
                                    string.format(L("Physical damage reduction: %.2f%%"), armorReduction),
                                    1,
                                    1,
                                    1,
                                    true
                                )
                                GameTooltip:AddLine(
                                    L("|cff888888(Against an evenly matched enemy)|r"),
                                    1,
                                    1,
                                    1,
                                    true
                                )
                            end

                            -- Reduction against target; same SECRET guard as Armor.
                            if C_PaperDollInfo and C_PaperDollInfo.GetArmorEffectivenessAgainstTarget then
                                local targetEff =
                                    C_PaperDollInfo.GetArmorEffectivenessAgainstTarget(shieldBlockArmor)
                                if targetEff and not issecretvalue(targetEff) and targetEff > 0 then
                                    GameTooltip:AddLine(
                                        string.format(L("(Against Current Target: %.2f%%)"), targetEff * 100),
                                        1,
                                        1,
                                        1,
                                        true
                                    )
                                end
                            end
                        end
                    end

                    GameTooltip:Show()
                    -- Glow the equipped items that grant this stat (opt-in per category)
                    local hk = sectionRec and sectionRec.settingKey
                    if
                        CludesUIDB
                        and (
                            (hk == "SecondaryStats" and CludesUIDB.highlightSecondaryItems)
                            or (hk == "Tertiary" and CludesUIDB.highlightTertiaryItems)
                        )
                    then
                        StartStatHighlights(statRow.name)
                    end
                end)

                valueButton:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                    StopStatHighlights()
                end)

                table.insert(GetFFD(widget).statsValues, {
                    value = amount,
                    func = statRow.func,
                    rawFunc = statRow.rawFunc,
                    format = statRow.format or "%d",
                    categoryKey = sectionRec.settingKey,
                })

                -- Store for collapse/expand (showWhen etc kept for later visibility checks)
                table.insert(sectionInfo.stats, {
                    label = caption,
                    value = amount,
                    button = valueButton,
                    showWhen = statRow.showWhen,
                    showCrestKey = statRow.showCrestKey,
                    showKey = statRow.showKey,
                    showIf = statRow.showIf,
                })

                -- Thin leader between label and value, vertically centered on
                -- the row and physical-pixel-perfect.
                do
                    local divider = sectionHolder:CreateTexture(nil, "OVERLAY")
                    divider:SetColorTexture(1, 1, 1, 0.06)
                    local Pix = CludesUI and CludesUI.PP
                    if Pix then
                        if Pix.DisablePixelSnap then
                            Pix.DisablePixelSnap(divider)
                        end
                        divider:SetHeight(Pix.mult or 1)
                    else
                        divider:SetHeight(1)
                    end
                    divider:SetPoint("LEFT", caption, "RIGHT", 10, 0)
                    divider:SetPoint("RIGHT", amount, "LEFT", -10, 0)
                    table.insert(sectionInfo.stats, { divider = divider })
                end

                statYOffset = statYOffset - 16
            end
        end

        sectionInfo.height = -statYOffset

        local function _applyCollapsedState()
            for _, statRow in ipairs(sectionInfo.stats) do
                if sectionInfo.isCollapsed then
                    if statRow.label then
                        statRow.label:Hide()
                    end
                    if statRow.value then
                        statRow.value:Hide()
                    end
                    if statRow.button then
                        statRow.button:Hide()
                    end
                    if statRow.divider then
                        statRow.divider:Hide()
                    end
                else
                    if statRow.label then
                        statRow.label:Show()
                    end
                    if statRow.value then
                        statRow.value:Show()
                    end
                    if statRow.button then
                        statRow.button:Show()
                    end
                    if statRow.divider then
                        statRow.divider:Show()
                    end
                end
            end
        end

        -- Restore saved collapsed state immediately (before first layout).
        if sectionInfo.isCollapsed then
            _applyCollapsedState()
        end

        titleHolder:SetScript("OnClick", function()
            sectionInfo.isCollapsed = not sectionInfo.isCollapsed
            _applyCollapsedState()
            -- Expand above shows every row unconditionally, including ones showWhen/
            -- showCrestKey correctly hid (e.g. Brewmaster's Stagger Effect); re-apply
            -- the real filter here (also recalculates layout, no separate call needed).
            RefreshStatsVisibility()

            -- Persist across sessions.
            if CludesUIDB then
                CludesUIDB.charSheetCollapsedSections = CludesUIDB.charSheetCollapsedSections or {}
                CludesUIDB.charSheetCollapsedSections[_collapseKey] = sectionInfo.isCollapsed or nil
            end
        end)

        -- Up/Down reorder arrows: up on LEFT edge, down on RIGHT, dividers between
        -- arrows and centered label. Always visible; first-up/last-down grayed + click-inert.
        do
            local arrowSize = 12
            local MEDIA = "Interface\\AddOns\\CludesUI\\media\\"
            local DIV_ICON_ALPHA = 1
            local DIV_ICON_HOVER = 1

            local function SaveOrder()
                if not CludesUIDB then
                    CludesUIDB = {}
                end
                CludesUIDB.statSectionsOrder = {}
                for _, sec in ipairs(GetFFD(widget).statsSections) do
                    table.insert(CludesUIDB.statSectionsOrder, sec.sectionTitle)
                end
            end

            local upButton = CreateFrame("Button", nil, titleHolder)
            upButton:SetSize(arrowSize, arrowSize)
            upButton:SetPoint("LEFT", titleHolder, "LEFT", 0, 0)
            upButton:SetFrameLevel(titleHolder:GetFrameLevel() + 2)
            local upIcon = upButton:CreateTexture(nil, "OVERLAY")
            upIcon:SetAllPoints()
            upIcon:SetTexture(MEDIA .. "icons\\cui-arrow-up3.png")
            upIcon:SetVertexColor(sectionRec.color.r, sectionRec.color.g, sectionRec.color.b, 1)
            upButton:SetAlpha(DIV_ICON_ALPHA)

            local downButton = CreateFrame("Button", nil, titleHolder)
            downButton:SetSize(arrowSize, arrowSize)
            downButton:SetPoint("RIGHT", titleHolder, "RIGHT", 0, 0)
            downButton:SetFrameLevel(titleHolder:GetFrameLevel() + 2)
            local downIcon = downButton:CreateTexture(nil, "OVERLAY")
            downIcon:SetAllPoints()
            downIcon:SetTexture(MEDIA .. "icons\\cui-arrow-down3.png")
            downIcon:SetVertexColor(sectionRec.color.r, sectionRec.color.g, sectionRec.color.b, 1)
            downButton:SetAlpha(DIV_ICON_ALPHA)

            -- Anchor the divider lines to hug the arrows
            leftStrip:ClearAllPoints()
            leftStrip:SetPoint("LEFT", upButton, "RIGHT", 6, 0)
            leftStrip:SetPoint("RIGHT", sectionTitle, "LEFT", -6, 0)
            rightStrip:ClearAllPoints()
            rightStrip:SetPoint("LEFT", sectionTitle, "RIGHT", 6, 0)
            rightStrip:SetPoint("RIGHT", downButton, "LEFT", -6, 0)

            upButton:SetScript("OnClick", function()
                for i, sec in ipairs(GetFFD(widget).statsSections) do
                    if sec == sectionInfo and i > 1 then
                        GetFFD(widget).statsSections[i], GetFFD(widget).statsSections[i - 1] =
                            GetFFD(widget).statsSections[i - 1], GetFFD(widget).statsSections[i]
                        SaveOrder()
                        GetFFD(widget).recalculateSections()
                        return
                    end
                end
            end)
            downButton:SetScript("OnClick", function()
                for i, sec in ipairs(GetFFD(widget).statsSections) do
                    if sec == sectionInfo and i < #GetFFD(widget).statsSections then
                        GetFFD(widget).statsSections[i], GetFFD(widget).statsSections[i + 1] =
                            GetFFD(widget).statsSections[i + 1], GetFFD(widget).statsSections[i]
                        SaveOrder()
                        GetFFD(widget).recalculateSections()
                        return
                    end
                end
            end)

            -- Stored so RecalculateSectionPositions can gray out boundary arrows
            sectionInfo.upBtn = upButton
            sectionInfo.downBtn = downButton
            sectionInfo.upIcon = upIcon
            sectionInfo.downIcon = downIcon
            sectionInfo._arrowAlpha = DIV_ICON_ALPHA
            sectionInfo._arrowHover = DIV_ICON_HOVER
        end

        sectionHolder:SetHeight(sectionInfo.height)
        offY = offY - sectionInfo.height - 6
    end

    scrollChild:SetHeight(-offY)

    if not (CludesUIDB and CludesUIDB.statSectionsOrder) then
        if not CludesUIDB then
            CludesUIDB = {}
        end
        CludesUIDB.statSectionsOrder = {}
        for _, sec in ipairs(GetFFD(widget).statsSections) do
            table.insert(CludesUIDB.statSectionsOrder, sec.sectionTitle)
        end
    end

    -- Initial visibility. RefreshStatsVisibility also settles opt-in rows (Mana,
    -- built unconditionally so toggles apply without /reload) before first OnShow.
    RefreshStatsVisibility()
    UpdateStatCategoryVisibility()
    -- Deferred pass: some settings (e.g. section visibility) may not be initialized yet.
    C_Timer.After(0, function()
        RefreshStatsVisibility()
        UpdateStatCategoryVisibility()
    end)

    -- Repaint every stat row.
    local function UpdateAllStats()
        local secondaryRaw = CludesUIDB and CludesUIDB.showSecondaryRaw
        local tertiaryRaw = CludesUIDB and CludesUIDB.showTertiaryRaw
        local secondaryBoth = CludesUIDB and CludesUIDB.showSecondaryBoth
        local tertiaryBoth = CludesUIDB and CludesUIDB.showTertiaryBoth
        for _, statEntry in ipairs(GetFFD(widget).statsValues) do
            -- Filtered-off rows stay in the list but off-screen; querying/formatting
            -- them wastes cycles on a path firing many times/sec. Test the row's OWN
            -- shown flag, not IsVisible() (false during the pre-panel-up build pass,
            -- which would leave every row reading "0" until the next event -- RefreshStatsVisibility repopulates).
            if statEntry.value and statEntry.value:IsShown() then
                local isSec = (statEntry.categoryKey == "SecondaryStats")
                local isTer = (statEntry.categoryKey == "Tertiary")
                local useBoth = statEntry.rawFunc and ((isSec and secondaryBoth) or (isTer and tertiaryBoth))
                local useRaw = (not useBoth) and ((isSec and secondaryRaw) or (isTer and tertiaryRaw))
                if useBoth then
                    local rawResult = statEntry.rawFunc()
                    local pctResult = statEntry.func and statEntry.func()
                    if rawResult ~= nil and pctResult ~= nil then
                        statEntry.value:SetText(format("%d (%.2f%%)", rawResult, pctResult))
                    else
                        statEntry.value:SetText("0")
                    end
                else
                    local fn = (useRaw and statEntry.rawFunc) or statEntry.func
                    local formatStr = useRaw and "%d" or statEntry.format
                    local result = fn and fn()
                    if result ~= nil then
                        statEntry.value:SetText(format(formatStr, result))
                    else
                        statEntry.value:SetText("0")
                    end
                end
            end
        end
    end
    CludesUI._refreshStatFormats = UpdateAllStats

    UpdateAllStats()

    -- Event-driven stat refresh: every stat the sheet displays updates on one of these events. Never poll this from an OnUpdate.
    local statsEventFrame = CreateFrame("Frame")
    local _STATS_EVENTS = {
        "UNIT_STATS",
        "COMBAT_RATING_UPDATE",
        "PLAYER_EQUIPMENT_CHANGED",
        "UNIT_ATTACK_POWER",
        "UNIT_RANGED_ATTACK_POWER",
        "UNIT_SPELL_HASTE",
        "UNIT_MAXPOWER",
        "MASTERY_UPDATE",
        "SPELL_POWER_CHANGED",
        "PLAYER_DAMAGE_DONE_MODS",
        "PLAYER_SPECIALIZATION_CHANGED",
        "HONOR_XP_UPDATE",
        "HONOR_LEVEL_UPDATE",
        "CURRENCY_DISPLAY_UPDATE",
    }
    -- One repaint per frame for this set and the spec set above: a stat
    -- change storms several events in one frame. A spec-side event also
    -- re-filters the rows, which repaints every row itself.
    do
        local flushFn = { pending = false, spec = false }
        flushFn.run = function()
            flushFn.pending = false
            local specInfo = flushFn.spec
            flushFn.spec = false
            if not widget:IsShown() then
                return
            end
            if specInfo then
                RefreshAttributeStats()
                RefreshStatsVisibility()
            elseif (widget.selectedTab or 1) == 1 then
                UpdateAllStats()
            end
        end
        GetFFD(widget).queueStats = function(specInfo)
            if specInfo then
                flushFn.spec = true
            end
            if flushFn.pending then
                return
            end
            flushFn.pending = true
            C_Timer.After(0, flushFn.run)
        end
    end
    statsEventFrame:SetScript("OnEvent", function(_, _, unitToken)
        -- Only a unit TOKEN filters: CURRENCY_DISPLAY_UPDATE passes a currency
        -- id, HONOR_LEVEL_UPDATE a boolean, PLAYER_EQUIPMENT_CHANGED a slot.
        if type(unitToken) == "string" and unitToken ~= "player" then
            return
        end
        GetFFD(widget).queueStats(false)
    end)
    -- Register only while the sheet is open: UNIT_STATS/COMBAT_RATING_UPDATE fire many times a second in combat, and dispatch alone is a measurable idle cost.
    widget:HookScript("OnShow", function()
        for _, ev in ipairs(_STATS_EVENTS) do
            statsEventFrame:RegisterEvent(ev)
        end
    end)
    widget:HookScript("OnHide", function()
        statsEventFrame:UnregisterAllEvents()
    end)
    -- The build runs inside the first OnShow, after that open's hooks fired.
    if widget:IsShown() then
        for _, ev in ipairs(_STATS_EVENTS) do
            statsEventFrame:RegisterEvent(ev)
        end
    end
    -- Refresh once on open, in case no event fired since the last close.
    widget:HookScript("OnShow", function()
        if widget and (widget.selectedTab or 1) == 1 then
            UpdateAllStats()
        end
    end)

    -- Rarity-colored border on a slot, replacing Blizzard's icon chrome.
    local function ApplyCustomSlotBorder(slotKey)
        local slotFrame = _G[slotKey]
        if not slotFrame then
            return
        end

        if slotFrame.IconBorder then
            slotFrame.IconBorder:Hide()
        end

        if slotFrame.IconOverlay then
            slotFrame.IconOverlay:Hide()
        end
        if slotFrame.IconOverlay2 then
            slotFrame.IconOverlay2:Hide()
        end

        if slotFrame.icon then
            local z = (CludesUIDB and CludesUIDB.charSheetIconZoom) or 0.07
            slotFrame.icon:SetTexCoord(z, 1 - z, z, 1 - z)
        end

        local normalTexture = _G[slotKey .. "NormalTexture"]
        if normalTexture then
            normalTexture:Hide()
        end

        local linkText = GetInventoryItemLink("player", slotFrame:GetID())
        local borderR, borderG, borderB = 0.4, 0.4, 0.4 -- Default dark gray
        if linkText then
            local _, _, quality = C_Item.GetItemInfo(linkText)
            if quality then
                borderR, borderG, borderB = C_Item.GetItemQualityColor(quality)
            end
        end

        -- Add border directly on the slot with item color (2px thickness)
        if CludesUI and CludesUI.PanelPP then
            CludesUI.PanelPP.CreateBorder(slotFrame, borderR, borderG, borderB, 1, 2, "OVERLAY", 1)
            local bdrFrame = CludesUI.PanelPP.GetBorders(slotFrame)
            if bdrFrame then
                bdrFrame:SetFrameLevel(slotFrame:GetFrameLevel())
            end
        end
    end

    -- Apply custom rarity borders to all item slots
    local slotList = {
        "CharacterHeadSlot",
        "CharacterNeckSlot",
        "CharacterShoulderSlot",
        "CharacterChestSlot",
        "CharacterWaistSlot",
        "CharacterLegsSlot",
        "CharacterFeetSlot",
        "CharacterWristSlot",
        "CharacterHandsSlot",
        "CharacterFinger0Slot",
        "CharacterFinger1Slot",
        "CharacterTrinket0Slot",
        "CharacterTrinket1Slot",
        "CharacterBackSlot",
        "CharacterMainHandSlot",
        "CharacterSecondaryHandSlot",
        "CharacterShirtSlot",
        "CharacterTabardSlot",
    }

    GetFFD(widget).themedSlots = slotList

    -- The top-row labels, the Titles panel, the relocated Equipment Manager
    -- pane and the Upgrades tab are the CludesUI sheet's own sidebar; the
    -- stock styles keep Blizzard's sidebar tabs and panes where they are.
    if not mod.CharSheetStock() then
        -- Top-row labels for the right column (Character, Titles, Equipment Manager)
        local buttonWidth = 64
        local buttonHeight = 25
        local buttonSpacing = -6
        -- Center buttons in right column (right column is ~268px wide starting at x=420)
        local totalButtonWidth = (buttonWidth * 3) + (buttonSpacing * 2)
        local rightColumnWidth = 268
        local startX = 425 + (rightColumnWidth - totalButtonWidth) / 2
        local startY = -60 -- Position near bottom of frame, but within bounds

        local topButtonRegistry = {}
        local function _paintTopButton(btnFrame)
            local textValue = btnFrame._text
            if not textValue then
                return
            end
            if btnFrame._active then
                local ACC = CludesUI.CLUDES_GREEN or { r = 0.51, g = 0.784, b = 1 }
                textValue:SetTextColor(ACC.r, ACC.g, ACC.b, 1)
            elseif btnFrame._disabled then
                textValue:SetTextColor(1, 1, 1, 0.25)
            elseif btnFrame._hover then
                textValue:SetTextColor(1, 1, 1, 1)
            else
                textValue:SetTextColor(1, 1, 1, 0.6)
            end
        end
        -- Mirrors Blizzard's sidebar state onto the labels and our panels: the
        -- shown pane's label is active and its stand-in panel (b._panel) shows, a
        -- disabled tab's label dims. Blizzard refreshes its tab state on every
        -- sheet open and pane switch, and this rides that refresh as a secure
        -- post-hook. The panels stay in OUR tree, never under Blizzard's panes:
        -- a pane's Show/Hide would run their scripts inside Blizzard's sidebar
        -- switch and taint the Equipment Manager rows it builds next.
        local function SyncTopButtons()
            for _, button in ipairs(topButtonRegistry) do
                local panel = GetPaperDollSideBarFrame and GetPaperDollSideBarFrame(button._paneIndex)
                button._active = (panel and panel:IsShown()) == true
                button._disabled = (button._tab and not button._tab:IsEnabled()) == true
                _paintTopButton(button)
                if button._panel then
                    button._panel:SetShown(button._active)
                end
            end
        end
        CludesUI.RegAccent({
            type = "callback",
            fn = function()
                for _, button in ipairs(topButtonRegistry) do
                    _paintTopButton(button)
                end
            end,
        })

        -- Labels only: each click lands on Blizzard's own sidebar tab seated over
        -- the label (below), so a pane switch is a real click on Blizzard's button
        -- and its panes build untainted (the gear flyout's Ignore This Slot and
        -- the set rows depend on it). Never click the tabs from our code.
        local function CreateCUIButton(name, caption, paneIndex)
            local btnFrame = CreateFrame("Frame", "CUI_CharSheet_" .. name, widget)
            btnFrame:SetSize(buttonWidth, buttonHeight)
            btnFrame:SetPoint("TOPLEFT", widget, "TOPLEFT", startX, startY)

            local textValue = btnFrame:CreateFontString(nil, "OVERLAY")
            textValue:SetFont(fontFile, 10, "")
            -- Anchor TOP (not CENTER) so the text sits flush with the top of the panel
            -- section instead of floating ~12px down inside a tall button.
            textValue:SetPoint("TOP", btnFrame, "TOP", 0, 0)
            textValue:SetText(caption)
            btnFrame._text = textValue
            btnFrame._active = false
            btnFrame._hover = false
            btnFrame._paneIndex = paneIndex
            btnFrame._tab = _G["PaperDollSidebarTab" .. paneIndex]
            _paintTopButton(btnFrame)

            table.insert(topButtonRegistry, btnFrame)
            return btnFrame
        end

        CreateCUIButton("Stats", L("Character"), 1)._panel = statsPane

        -- Titles panel (same position and size as stats panel); SyncTopButtons
        -- shows it while Blizzard's Titles pane is the shown sidebar.
        local titlesPane = CreateFrame("Frame", "CUI_CharSheet_TitlesPanel", widget)
        titlesPane:SetWidth(190)
        titlesPane:SetPoint("TOPLEFT", statsPane, "TOPLEFT", 0, 0)
        titlesPane:SetPoint("BOTTOMLEFT", statsPane, "BOTTOMLEFT", 0, 0)
        titlesPane:SetFrameLevel(50)
        titlesPane:Hide()
        GetFFD(widget).titlesPanel = titlesPane

        -- Titles panel has no backdrop of its own; it uses the shared statsBg.

        local titleSearch = CreateFrame("EditBox", "CUI_CharSheet_TitlesSearchBox", titlesPane)
        titleSearch:SetSize(180, 24)
        titleSearch:SetPoint("TOPLEFT", titlesPane, "TOPLEFT", 0, -30)
        titleSearch:SetAutoFocus(false)
        titleSearch:SetMaxLetters(20)

        local searchBg = titleSearch:CreateTexture(nil, "BACKGROUND")
        searchBg:SetColorTexture(0, 0, 0, 0.5)
        searchBg:SetAllPoints()

        titleSearch:SetTextColor(1, 1, 1, 1)
        titleSearch:SetFont(fontFile, 10, "")
        titleSearch:SetTextInsets(4, 4, 0, 0)

        local hintText = titleSearch:CreateFontString(nil, "OVERLAY")
        hintText:SetFont(fontFile, 10, "")
        hintText:SetText(L("Search titles..."))
        hintText:SetTextColor(0.6, 0.6, 0.6, 0.7)
        hintText:SetPoint("LEFT", titleSearch, "LEFT", 4, 0)

        -- Clear "x" (visible only when the search box has text). Invisible click
        -- target sits on top of the glyph so it can be clicked to clear.
        local clearX = titleSearch:CreateFontString(nil, "OVERLAY")
        clearX:SetFont(fontFile, 11, "")
        clearX:SetText("x")
        clearX:SetTextColor(0.7, 0.7, 0.7, 1)
        clearX:SetPoint("RIGHT", titleSearch, "RIGHT", -4, 0)
        clearX:Hide()

        local clearHit = CreateFrame("Button", nil, titleSearch)
        clearHit:SetSize(14, 14)
        clearHit:SetPoint("CENTER", clearX, "CENTER", 0, 0)
        clearHit:Hide()
        clearHit:SetScript("OnClick", function()
            titleSearch:SetText("")
            titleSearch:ClearFocus()
        end)

        local titlesScroller = CreateFrame("ScrollFrame", "CUI_CharSheet_TitlesScrollFrame", titlesPane)
        titlesScroller:SetPoint("TOPLEFT", titlesPane, "TOPLEFT", 0, -65)
        titlesScroller:SetPoint("BOTTOMRIGHT", titlesPane, "BOTTOMRIGHT", 0, 0)
        titlesScroller:EnableMouseWheel(true)

        local titlesScrollChild = CreateFrame("Frame", "CUI_CharSheet_TitlesScrollChild", titlesScroller)
        titlesScrollChild:SetWidth(180)
        titlesScroller:SetScrollChild(titlesScrollChild)

        -- Custom scrollbar (same shape as the stats scrollbar).
        AttachCustomScrollbar(titlesScroller, titlesScrollChild, {
            trackOwner = titlesPane,
            topInset = -65, -- matches titlesScrollFrame's top anchor offset
        })

        local titleButtons = {} -- Persistent button registry (hoisted so click handlers can repaint without rebuild)
        local selectedTitleIndex = nil

        -- Repaints only the previous + new selection (O(1) instead of O(n) over
        -- the full title list). Falls back to a full sweep when prev is unset.
        local function PaintTitleSelection(newIndex)
            local prev = selectedTitleIndex
            selectedTitleIndex = newIndex
            local ACC = CludesUI.CLUDES_GREEN or { r = 0.51, g = 0.784, b = 1 }
            if prev ~= nil then
                local oldData = titleButtons[prev]
                if oldData and oldData.bg then
                    oldData.bg:SetColorTexture(1, 1, 1, 0.04)
                end
                local newData = titleButtons[newIndex]
                if newData and newData.bg then
                    newData.bg:SetColorTexture(ACC.r, ACC.g, ACC.b, 0.5)
                end
            else
                for position, btnData in pairs(titleButtons) do
                    if position == newIndex then
                        btnData.bg:SetColorTexture(ACC.r, ACC.g, ACC.b, 0.5)
                    else
                        btnData.bg:SetColorTexture(1, 1, 1, 0.04)
                    end
                end
            end
        end

        -- Physical-pixel-snapped tile step: 24px tile + 2px gap, aligned to PP.mult
        local _PP_MULT = (CludesUI and CludesUI.PanelPP and CludesUI.PanelPP.mult) or 1
        local TILES_TILE_H = 24
        local TILES_TILE_GAP = math.max(_PP_MULT, math.floor(2 / _PP_MULT + 0.5) * _PP_MULT)
        local TILES_TILE_STEP = TILES_TILE_H + TILES_TILE_GAP

        local _titlesBuilt = false
        local _titlesOrder = {} -- cached alphabetical index order; rebuilt with the button list

        -- One-time factory: reusable button with once-bound scripts. Data travels via
        -- btn._titleIndex / btn._titleName, so scripts never close over per-title state.
        local function _createTitleButton(titleIndex)
            local btnFrame = CreateFrame("Button", nil, titlesScrollChild)
            btnFrame:SetWidth(180)
            btnFrame:SetHeight(TILES_TILE_H)

            btnFrame._bg = btnFrame:CreateTexture(nil, "BACKGROUND")
            btnFrame._bg:SetColorTexture(1, 1, 1, 0.05)
            btnFrame._bg:SetAllPoints()

            btnFrame._hover = btnFrame:CreateTexture(nil, "ARTWORK")
            btnFrame._hover:SetColorTexture(1, 1, 1, 0.1)
            btnFrame._hover:SetAllPoints()
            btnFrame._hover:Hide()

            btnFrame._text = btnFrame:CreateFontString(nil, "OVERLAY")
            btnFrame._text:SetFont(fontFile, 11, "")
            btnFrame._text:SetTextColor(1, 1, 1, 1)
            btnFrame._text:SetPoint("LEFT", btnFrame, "LEFT", 10, 0)

            btnFrame._titleIndex = titleIndex
            btnFrame:SetScript("OnEnter", function(self)
                self._hover:Show()
            end)
            btnFrame:SetScript("OnLeave", function(self)
                self._hover:Hide()
            end)
            btnFrame:SetScript("OnClick", function(self)
                SetCurrentTitle(self._titleIndex)
                PaintTitleSelection(self._titleIndex)
            end)
            return btnFrame
        end

        -- Build every known title button ONCE. No rebuild on search keystrokes.
        local function BuildTitlesList()
            if _titlesBuilt then
                return
            end
            _titlesBuilt = true

            -- "No Title": titleId -1 clears the title (1+ are real titles). 0 is a
            -- silent no-op and leaves the server-saved title in place across logins.
            local noTitleBtn = _createTitleButton(-1)
            noTitleBtn._text:SetText(L("No Title"))
            titleButtons[-1] = { btn = noTitleBtn, bg = noTitleBtn._bg }

            for titleIndex = 1, GetNumTitles() do
                if IsTitleKnown(titleIndex) then
                    local titleName = GetTitleName(titleIndex)
                    if titleName then
                        local btnFrame = _createTitleButton(titleIndex)
                        btnFrame._titleName = titleName
                        btnFrame._text:SetText(titleName)
                        titleButtons[titleIndex] = { btn = btnFrame, bg = btnFrame._bg }
                    end
                end
            end

            -- Sort alphabetically, "No Title" (-1) pinned first. Title names carry a "%s"
            -- player-name placeholder (prefix/suffix) plus spaces; strip both so the sort
            -- key is the meaningful word ("%s the Kingslayer" -> "the kingslayer"). Computed once, never per keystroke.
            local function SortKey(position)
                local name = titleButtons[position].btn._titleName or ""
                name = name:gsub("%%s", " "):gsub("^%s+", ""):gsub("%s+$", "")
                return name:lower()
            end
            wipe(_titlesOrder)
            for position in pairs(titleButtons) do
                _titlesOrder[#_titlesOrder + 1] = position
            end
            table.sort(_titlesOrder, function(a, button)
                if a == -1 then
                    return true
                end
                if button == -1 then
                    return false
                end
                return SortKey(a) < SortKey(button)
            end)
        end

        -- Filter: show/hide + reposition visible buttons by current search text.
        local function FilterTitlesList()
            BuildTitlesList()

            local searchText = (titleSearch:GetText() or ""):lower()
            local offY = 0

            for _, position in ipairs(_titlesOrder) do
                local btnData = titleButtons[position]
                local btnFrame = btnData.btn
                local name = (position == -1) and L("No Title") or (btnFrame._titleName or "")
                local visible = (searchText == "")
                    or (position == -1) -- keep "No Title" always visible
                    or name:lower():find(searchText, 1, true)
                if visible then
                    btnFrame:ClearAllPoints()
                    btnFrame:SetPoint("TOPLEFT", titlesScrollChild, "TOPLEFT", 0, offY)
                    btnFrame:Show()
                    offY = offY - TILES_TILE_STEP
                else
                    btnFrame:Hide()
                end
            end

            PaintTitleSelection(GetCurrentTitle())
            titlesScrollChild:SetHeight(-offY)
            titlesScroller:SetVerticalScroll(0)
        end

        -- Alias: some call sites say RefreshTitlesList().
        local RefreshTitlesList = FilterTitlesList

        -- Learning a title invalidates the build cache so the next filter rebuilds;
        -- the event is rare enough that one full rebuild on that edge is fine.
        local _titlesInvalidator = CreateFrame("Frame")
        _titlesInvalidator:RegisterEvent("KNOWN_TITLES_UPDATE")
        _titlesInvalidator:SetScript("OnEvent", function()
            _titlesBuilt = false
            wipe(_titlesOrder)
            for position, payload in pairs(titleButtons) do
                if payload.btn then
                    payload.btn:Hide()
                end
                titleButtons[position] = nil
            end
        end)

        titleSearch:SetScript("OnTextChanged", function(self)
            if (self:GetText() or "") ~= "" then
                clearX:Show()
                clearHit:Show()
            else
                clearX:Hide()
                clearHit:Hide()
            end
            RefreshTitlesList()
        end)

        titleSearch:SetScript("OnEditFocusGained", function()
            if titleSearch:GetText() == "" then
                hintText:Hide()
            end
        end)

        titleSearch:SetScript("OnEditFocusLost", function()
            if titleSearch:GetText() == "" then
                hintText:Show()
            end
        end)

        -- Escape clears focus (and is consumed -- do NOT propagate, that would
        -- send every typed character to action bar bindings too).
        titleSearch:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
        end)

        RefreshTitlesList()

        GetFFD(widget).titlesPanel:HookScript("OnShow", function()
            titleSearch:SetText("")
            RefreshTitlesList()
        end)

        CreateCUIButton("Titles", L("Titles"), 2)._panel = titlesPane
        CreateCUIButton("Equipment", L("Equipment"), 3)

        -- Labels chain from the stats panel's TOPLEFT and span its full width.
        -- Frame level is raised above the stats panel so statsBg doesn't cover them.
        -- Each label's Blizzard sidebar tab is seated over it one level up, with
        -- the tab's own art faded out (Blizzard re-shows those regions on every
        -- tab refresh, so alpha is the channel); hovering the tab paints the label.
        -- The tab keeps its native tooltip, which also says why a dimmed label's
        -- pane is unavailable.
        local SIDEBAR_TAB_ART = { "TabBg", "Icon", "Hider", "Highlight" }
        for i, btnFrame in ipairs(topButtonRegistry) do
            btnFrame:ClearAllPoints()
            btnFrame:SetPoint("TOPLEFT", statsPane, "TOPLEFT", (i - 1) * (buttonWidth + buttonSpacing), 0)
            btnFrame:SetFrameLevel(statsPane:GetFrameLevel() + 2)
            local tabBtn = btnFrame._tab
            if tabBtn then
                tabBtn:ClearAllPoints()
                tabBtn:SetAllPoints(btnFrame)
                tabBtn:SetFrameLevel(btnFrame:GetFrameLevel() + 1)
                for _, key in ipairs(SIDEBAR_TAB_ART) do
                    local regionFrame = tabBtn[key]
                    if regionFrame then
                        regionFrame:SetAlpha(0)
                    end
                end
                tabBtn:HookScript("OnEnter", function()
                    btnFrame._hover = true
                    _paintTopButton(btnFrame)
                end)
                tabBtn:HookScript("OnLeave", function()
                    btnFrame._hover = false
                    _paintTopButton(btnFrame)
                end)
            end
        end
        hooksecurefunc("PaperDollFrame_UpdateSidebarTabs", SyncTopButtons)
        SyncTopButtons()

        -- Blizzard's Equipment Manager pane moves into the column under the
        -- labels. Its list is never resized or measured from here: a size change
        -- runs the list's update (and so its row build) in the caller's context,
        -- and the rows must only ever be built by Blizzard's own code. Its native
        -- button row + list (354px) is taller than the column, so the WHOLE pane
        -- is scaled to fit instead: every frame inside keeps its own width and
        -- height, so no size handler runs. Offsets on the pane are in its units.
        local emPane = _G.PaperDollFrame and _G.PaperDollFrame.EquipmentManagerPane
        if emPane then
            local EM_PANE_SCALE = 0.85
            emPane:SetScale(EM_PANE_SCALE)
            emPane:ClearAllPoints()
            emPane:SetPoint("TOPLEFT", statsPane, "TOPLEFT", 0, -27 / EM_PANE_SCALE)
            emPane:SetFrameLevel(statsPane:GetFrameLevel() + 1)
            if emPane.ScrollBox then
                emPane.ScrollBox:ClearAllPoints()
                emPane.ScrollBox:SetPoint("TOPLEFT", emPane, "TOPLEFT", 0, -23)
            end

            -- Equip / Save and the scroll bar trade Blizzard's red panel-button
            -- and trim art for the house look. Art is faded and our textures and
            -- borders are added beside it; no field, size or script of Blizzard's
            -- is written, so the pane's own code runs as before.
            local WS = mod.WSkin
            if WS then
                local emButtons = {
                    emPane.EquipSet or _G.PaperDollFrameEquipSet,
                    emPane.SaveSet or _G.PaperDollFrameSaveSet,
                }
                for _, button in ipairs(emButtons) do
                    WS.Button(button)
                end
                -- Labels: white while enabled, gray while not, painted after
                -- Blizzard's own update. Never from the buttons' OnEnable /
                -- OnDisable: the update toggles them before it writes the set
                -- list, so a hook there would run inside it. The flyout's Ignore
                -- This Slot enables Save outside the update; that label keeps
                -- Blizzard's color until the next update.
                local function PaintEMLabels()
                    if
                        CludesUIDB
                        and (CludesUIDB.themedCharacterSheet == false or CludesUI.BlizzWindowSkinsKilled())
                    then
                        return
                    end
                    for _, button in ipairs(emButtons) do
                        local labelText = button.Text or button:GetFontString()
                        if labelText then
                            if button:IsEnabled() then
                                WS.White(labelText)
                            else
                                labelText:SetTextColor(0.5, 0.5, 0.5)
                            end
                        end
                    end
                end
                hooksecurefunc("PaperDollEquipmentManagerPane_Update", PaintEMLabels)
                PaintEMLabels()
                local sb = emPane.ScrollBar
                if sb then
                    WS.ScrollBar(sb)
                    -- WowTrimScrollBar keeps its trough on a child frame that
                    -- WS.ScrollBar does not reach.
                    if sb.Background then
                        WS.FadeRegions(sb.Background)
                    end
                end
            end

            -- Blizzard seats the button row flush on the list, with the slack
            -- above it. Lift the row by its own anchor so the gap splits evenly;
            -- a button chained to its sibling follows it. Moving the buttons
            -- leaves the list's size alone.
            local EM_BUTTON_LIFT = 8
            local equipBtn = emPane.EquipSet or _G.PaperDollFrameEquipSet
            local saveBtn = emPane.SaveSet or _G.PaperDollFrameSaveSet
            for _, button in ipairs({ equipBtn, saveBtn }) do
                local anchors, chained = {}, false
                for i = 1, button:GetNumPoints() do
                    local a = { button:GetPoint(i) }
                    if a[2] == equipBtn or a[2] == saveBtn then
                        chained = true
                    end
                    anchors[i] = a
                end
                if not chained and #anchors > 0 then
                    button:ClearAllPoints()
                    for _, a in ipairs(anchors) do
                        button:SetPoint(a[1], a[2], a[3], a[4], a[5] + EM_BUTTON_LIFT)
                    end
                end
            end

            -- The list and the button row fill the column like the other panes.
            -- Their widths change only through a restricted Execute: a list resize
            -- runs the list's update, and its rows must only ever be built by
            -- Blizzard's own code, which a restricted snippet keeps untainted. A
            -- restricted handle reaches an unprotected frame only out of combat, so
            -- a sheet skinned in combat widens when the fight ends. A frame with
            -- access constraints or forbidden aspects is left alone: the snippet
            -- would pass forbidden on to every frame it referenced.
            local entries = emPane.ScrollBox
            if entries and equipBtn and saveBtn then
                -- Pane units; the scroll bar keeps its 8 px gap and 8 px width.
                local listW = math.floor(statsPane:GetWidth() / EM_PANE_SCALE) - 16
                local function WidenEquipmentPane()
                    for _, frame in ipairs({ entries, equipBtn, saveBtn }) do
                        if frame:HasAccessConstraints() or frame:HasAnyForbiddenAspects() then
                            return
                        end
                    end
                    local sizer = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
                    SecureHandlerSetFrameRef(sizer, "list", entries)
                    SecureHandlerSetFrameRef(sizer, "equip", equipBtn)
                    SecureHandlerSetFrameRef(sizer, "save", saveBtn)
                    sizer:SetAttribute("listW", listW)
                    sizer:SetAttribute("btnW", math.floor(listW / 2))
                    SecureHandlerExecute(
                        sizer,
                        [[
                    self:GetFrameRef("list"):SetWidth(self:GetAttribute("listW"))
                    self:GetFrameRef("equip"):SetWidth(self:GetAttribute("btnW"))
                    self:GetFrameRef("save"):SetWidth(self:GetAttribute("btnW"))
                ]]
                    )
                end
                if InCombatLockdown() then
                    mod.CombatQueue.Defer("CharSheetEquipmentWidth", WidenEquipmentPane)
                else
                    WidenEquipmentPane()
                end
            end
        end

        -- Gear set rows trade Blizzard's stat-strip art for the sheet's flat
        -- look. A post-hook on Blizzard's row initializer, so it re-applies after
        -- every (re)build; it touches regions only, never the row's own fields.
        local SET_ROW_ART = { "BgTop", "BgMiddle", "BgBottom" }
        hooksecurefunc("PaperDollEquipmentManagerPane_InitButton", function(btnFrame)
            if
                CludesUIDB
                and (CludesUIDB.themedCharacterSheet == false or CludesUI.BlizzWindowSkinsKilled())
            then
                return
            end
            for i = 1, #SET_ROW_ART do
                local regionFrame = btnFrame[SET_ROW_ART[i]]
                if regionFrame then
                    regionFrame:SetAlpha(0)
                end
            end
            -- Blizzard stripes every other row; every row gets the same faint
            -- tile instead, matching the Titles list.
            local stripe = btnFrame.Stripe
            if stripe then
                stripe:SetColorTexture(1, 1, 1, 1)
                stripe:SetAlpha(0.04)
                stripe:Show()
            end
            local ACC = CludesUI.CLUDES_GREEN or { r = 0.51, g = 0.784, b = 1 }
            local selected = btnFrame.SelectedBar
            if selected then
                selected:SetColorTexture(ACC.r, ACC.g, ACC.b, 1)
                selected:SetBlendMode("BLEND")
                selected:SetAlpha(0.2)
            end
            local hover = btnFrame.HighlightBar
            if hover then
                hover:SetColorTexture(1, 1, 1, 1)
                hover:SetBlendMode("BLEND")
                hover:SetAlpha(0.08)
            end
            local caption = btnFrame.text
            if caption then
                caption:SetFont(fontFile, 11, "")
                -- The name runs to the check mark, so the widened rows show
                -- longer names.
                caption:SetPoint("RIGHT", btnFrame, "RIGHT", -24, 0)
                -- Gold set names read white here; red (items missing) and the
                -- green New Set label stay as Blizzard colours them.
                if btnFrame.setID then
                    local _, _, _, _, _, _, _, numLost = C_EquipmentSet.GetEquipmentSetInfo(btnFrame.setID)
                    if (numLost or 0) == 0 then
                        caption:SetTextColor(1, 1, 1, 1)
                    end
                end
            end
        end)

        -- Calc tab is created lazily by ApplyCharSheetCalcTab when showCalcButton is on.
        if CludesUI.ApplyCharSheetCalcTab then
            CludesUI.ApplyCharSheetCalcTab()
        end
    end -- not ns.CharSheetStock()

    -- Left column slots (show itemlevel on right)
    local leftColumnSlots = {
        "CharacterHeadSlot",
        "CharacterNeckSlot",
        "CharacterShoulderSlot",
        "CharacterBackSlot",
        "CharacterChestSlot",
        "CharacterShirtSlot",
        "CharacterTabardSlot",
        "CharacterWristSlot",
    }

    -- Right column slots (show itemlevel on left)
    local rightColumnSlots = {
        "CharacterHandsSlot",
        "CharacterWaistSlot",
        "CharacterLegsSlot",
        "CharacterFeetSlot",
        "CharacterFinger0Slot",
        "CharacterFinger1Slot",
        "CharacterTrinket0Slot",
        "CharacterTrinket1Slot",
    }

    local fontFile = CludesUI.GetFontPath("blizzardSkin") or STANDARD_TEXT_FONT

    -- Create overlay frame for text labels (above model, transparent, no mouse input).
    -- Stock styles: a PaperDollFrame child (hides with the Character tab) above
    -- Blizzard's model scene and below its slot frame (PaperDollItemsFrame, 100).
    local textLayer
    if mod.CharSheetStock() then
        local scene = _G.CharacterModelScene
        textLayer = CreateFrame("Frame", "CUI_CharSheet_TextOverlay", _G.PaperDollFrame or widget)
        textLayer:SetFrameLevel((scene and scene:GetFrameLevel() or 50) + 10)
    else
        textLayer = CreateFrame("Frame", "CUI_CharSheet_TextOverlay", widget)
        -- Above the model, whose level PreSkin sets from CharacterFrame's.
        local model = GetFFD(widget).modelScene
        textLayer:SetFrameLevel((model and model:GetFrameLevel() or widget:GetFrameLevel()) + 10)
    end
    textLayer:EnableMouse(false)
    textLayer:Show()
    GetFFD(widget).textOverlayFrame = textLayer

    -- Top-left eyeball toggle: temporarily hides all item slot text (item level,
    -- upgrade track, enchants) by alpha-ing the shared overlay. Session-only.
    -- Not on the stock styles: that corner is Blizzard's portrait.
    if not mod.CharSheetStock() then
        local EYE_VISIBLE = CludesUI.EYE_VISIBLE_ICON
        local EYE_INVISIBLE = CludesUI.EYE_INVISIBLE_ICON
        local hidden = false
        local eyeBtn = CreateFrame("Button", "CUI_CharSheet_TextEyeBtn", widget)
        eyeBtn:SetSize(20, 20)
        eyeBtn:SetPoint("TOPLEFT", widget, "TOPLEFT", 14, -6)
        eyeBtn:SetFrameLevel(widget:GetFrameLevel() + 20)
        eyeBtn:SetAlpha(0.4)
        local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()
        eyeTex:SetTexture(EYE_VISIBLE)
        eyeBtn:SetScript("OnClick", function()
            hidden = not hidden
            eyeTex:SetTexture(hidden and EYE_INVISIBLE or EYE_VISIBLE)
            if GetFFD(widget).textOverlayFrame then
                GetFFD(widget).textOverlayFrame:SetAlpha(hidden and 0 or 1)
            end
        end)
        eyeBtn:SetScript("OnEnter", function(self)
            self:SetAlpha(0.8)
            CludesUI.ShowWidgetTooltip(self, hidden and "Show Item Text" or "Hide Item Text", { width = 135 })
        end)
        eyeBtn:SetScript("OnLeave", function(self)
            self:SetAlpha(0.4)
            CludesUI.HideWidgetTooltip()
        end)
        GetFFD(widget).textEyeBtn = eyeBtn
    end

    -- Label offsets from the slot edge. The stock styles keep Blizzard's
    -- bronze slot frames, which reach about 8px past each slot, so their
    -- labels sit further out; they also keep Blizzard's own slot borders.
    do
        local LX = mod.CharSheetStock() and 22 or 15 -- item level (centre)
        local EX = mod.CharSheetStock() and 12 or 5 -- enchant (near edge)
        -- Stat letter labels in the slot icon's bottom-left corner ("MH", the
        -- tertiaries smaller above them: "L"), built for a slot the first time
        -- Stat Letters has an item there (nothing at all while the option is off).
        -- They sit on the icon, so their frame is above the slots and the gem
        -- icons (100); the stock styles' slots live in PaperDollItemsFrame (100)
        -- and sit above that. A child of the text overlay, so the eye toggle hides
        -- them with the other item text.
        local statLetterFrame
        GetFFD(widget).statLetterLabels = function(slotFrame)
            local skinData = GetFFD(slotFrame)
            if skinData.statLetterLabel then
                return skinData.statLetterLabel, skinData.statLetterTerLabel
            end
            if not statLetterFrame then
                statLetterFrame = CreateFrame("Frame", nil, textLayer)
                local headSlot = _G.CharacterHeadSlot
                statLetterFrame:SetFrameLevel(math.max(100, headSlot and headSlot:GetFrameLevel() or 0) + 10)
                statLetterFrame:EnableMouse(false)
            end
            local flag = CludesUI.SlugFlag("OUTLINE, SLUG")
            local statCaption = statLetterFrame:CreateFontString(nil, "OVERLAY")
            statCaption:SetFont(fontFile, 11, flag)
            statCaption:SetPoint("BOTTOMLEFT", slotFrame, "BOTTOMLEFT", 4, 2)
            statCaption:SetTextColor(1, 1, 1, 0.95)
            local terLabel = statLetterFrame:CreateFontString(nil, "OVERLAY")
            terLabel:SetFont(fontFile, 9, flag)
            terLabel:SetPoint("BOTTOMLEFT", statCaption, "TOPLEFT", 0, 0)
            terLabel:SetTextColor(0.94, 0.66, 0.94, 0.95)
            skinData.statLetterLabel, skinData.statLetterTerLabel = statCaption, terLabel
            return statCaption, terLabel
        end
        for _, slotKey in ipairs(slotList) do
            if not mod.CharSheetStock() then
                ApplyCustomSlotBorder(slotKey)
            end

            -- Shirt/tabard: skin the border but never show item level / upgrade track /
            -- enchant text -- no stats worth showing, and the labels clutter the model.
            local skipLabels = (slotKey == "CharacterShirtSlot" or slotKey == "CharacterTabardSlot")

            -- Create itemlevel labels
            local slotFrame = _G[slotKey]
            if slotFrame and not GetFFD(slotFrame).itemLevelLabel and not skipLabels then
                local itemLevelSize = CludesUIDB and CludesUIDB.charSheetItemLevelSize or 11
                local caption = textLayer:CreateFontString(nil, "OVERLAY")
                caption:SetFont(fontFile, itemLevelSize, "")
                caption:SetTextColor(1, 1, 1, 0.8)
                caption:SetJustifyH("CENTER")

                -- Placed on the outer side of the slot's column.
                if tContains(leftColumnSlots, slotKey) then
                    caption:SetPoint("CENTER", slotFrame, "RIGHT", LX, 10)
                elseif tContains(rightColumnSlots, slotKey) then
                    caption:SetPoint("CENTER", slotFrame, "LEFT", -LX, 10)
                elseif slotKey == "CharacterMainHandSlot" then
                    caption:SetPoint("CENTER", slotFrame, "LEFT", -LX, 10)
                elseif slotKey == "CharacterSecondaryHandSlot" then
                    caption:SetPoint("CENTER", slotFrame, "RIGHT", LX, 10)
                end

                GetFFD(slotFrame).itemLevelLabel = caption
            end

            -- Create enchant labels
            if slotFrame and not GetFFD(slotFrame).enchantLabel and not skipLabels then
                local enchantSize = CludesUIDB and CludesUIDB.charSheetEnchantSize or 9
                local enchantLabel = textLayer:CreateFontString(nil, "OVERLAY")
                enchantLabel:SetFont(fontFile, enchantSize, "")
                enchantLabel:SetTextColor(1, 1, 1, 0.8)

                -- Below the itemlevel, justified toward the icon so a width-capped
                -- enchant name hugs its slot: left column left-aligned, right column
                -- right-aligned (weapon slots follow their anchor side).
                if tContains(leftColumnSlots, slotKey) then
                    enchantLabel:SetPoint("LEFT", slotFrame, "RIGHT", EX, -5)
                    enchantLabel:SetJustifyH("LEFT")
                elseif tContains(rightColumnSlots, slotKey) then
                    enchantLabel:SetPoint("RIGHT", slotFrame, "LEFT", -EX, -5)
                    enchantLabel:SetJustifyH("RIGHT")
                elseif slotKey == "CharacterMainHandSlot" then
                    enchantLabel:SetPoint("RIGHT", slotFrame, "LEFT", -EX, -5)
                    enchantLabel:SetJustifyH("RIGHT")
                elseif slotKey == "CharacterSecondaryHandSlot" then
                    enchantLabel:SetPoint("LEFT", slotFrame, "RIGHT", EX, -5)
                    enchantLabel:SetJustifyH("LEFT")
                else
                    enchantLabel:SetJustifyH("CENTER")
                end

                local hoverFrame = CreateFrame("Frame", nil, textLayer)
                hoverFrame:SetSize(20, 20)
                hoverFrame:SetFrameLevel(textLayer:GetFrameLevel() + 20)
                if tContains(leftColumnSlots, slotKey) then
                    hoverFrame:SetPoint("LEFT", slotFrame, "RIGHT", EX, -5)
                elseif tContains(rightColumnSlots, slotKey) then
                    hoverFrame:SetPoint("RIGHT", slotFrame, "LEFT", -EX, -5)
                elseif slotKey == "CharacterMainHandSlot" then
                    hoverFrame:SetPoint("RIGHT", slotFrame, "LEFT", -EX, -5)
                elseif slotKey == "CharacterSecondaryHandSlot" then
                    hoverFrame:SetPoint("LEFT", slotFrame, "RIGHT", EX, -5)
                end
                hoverFrame:EnableMouse(true)
                hoverFrame:Hide()

                GetFFD(slotFrame).enchantLabel = enchantLabel
                GetFFD(slotFrame).enchantHoverFrame = hoverFrame
            end

            -- Create upgrade track labels (positioned relative to itemlevel)
            if slotFrame and not GetFFD(slotFrame).upgradeTrackLabel and GetFFD(slotFrame).itemLevelLabel then
                local upgradeTrackSize = CludesUIDB and CludesUIDB.charSheetUpgradeTrackSize or 11
                local upgradeTrackLabel = textLayer:CreateFontString(nil, "OVERLAY")
                upgradeTrackLabel:SetFont(fontFile, upgradeTrackSize, "")
                upgradeTrackLabel:SetTextColor(1, 1, 1, 0.6)
                upgradeTrackLabel:SetJustifyH("CENTER")

                -- Beside the itemlevel label, on the model-facing side of the column.
                if tContains(leftColumnSlots, slotKey) then
                    upgradeTrackLabel:SetPoint("LEFT", GetFFD(slotFrame).itemLevelLabel, "RIGHT", 3, 0)
                elseif tContains(rightColumnSlots, slotKey) then
                    upgradeTrackLabel:SetPoint("RIGHT", GetFFD(slotFrame).itemLevelLabel, "LEFT", -3, 0)
                elseif slotKey == "CharacterMainHandSlot" then
                    upgradeTrackLabel:SetPoint("RIGHT", GetFFD(slotFrame).itemLevelLabel, "LEFT", -3, 0)
                elseif slotKey == "CharacterSecondaryHandSlot" then
                    upgradeTrackLabel:SetPoint("LEFT", GetFFD(slotFrame).itemLevelLabel, "RIGHT", 3, 0)
                end

                GetFFD(slotFrame).upgradeTrackLabel = upgradeTrackLabel
            end
        end
    end -- label offsets

    local function UpdateSlotBorders()
        for _, slotKey in ipairs(slotList) do
            local slotFrame = _G[slotKey]
            if slotFrame then
                local linkText = GetInventoryItemLink("player", slotFrame:GetID())
                local borderR, borderG, borderB = 0.4, 0.4, 0.4 -- Default dark gray
                if linkText then
                    local quality = C_Item.GetItemQualityByID(linkText)
                    if quality then
                        borderR, borderG, borderB = C_Item.GetItemQualityColor(quality)
                    end
                end
                if CludesUI and CludesUI.PanelPP then
                    CludesUI.PanelPP.SetBorderColor(slotFrame, borderR, borderG, borderB, 1)
                end
            end
        end
    end

    -- Shared pulse ticker: every slot needing the red "missing enchant" pulse uses this one OnUpdate. Zero cost when empty (ticker self-hides).
    -- Parented to the Character tab, so the OnUpdate stops whenever the sheet
    -- (or that tab) closes, even while a flagged slot is still in the set.
    local missingEnchantSlots = {}
    local pulseTicker = CreateFrame("Frame", nil, _G.PaperDollFrame or widget)
    pulseTicker:Hide()
    pulseTicker:SetScript("OnUpdate", function()
        -- 1.5s sin cycle between alpha 0.25 and 1.0
        local t = GetTime()
        local alpha = 0.25 + 0.75 * (0.5 + 0.5 * math.sin(t * math.pi / 0.75))
        for slotFrame in pairs(missingEnchantSlots) do
            local shade = GetFFD(slotFrame).missingEnchBorder
            if shade then
                shade:SetAlpha(alpha)
            end
        end
    end)

    local function SetSlotMissingEnchant(slotFrame, missing)
        if missing then
            if not GetFFD(slotFrame).missingEnchBorder then
                local overlayFrame = CreateFrame("Frame", nil, slotFrame)
                overlayFrame:SetAllPoints(slotFrame)
                overlayFrame:SetFrameLevel(slotFrame:GetFrameLevel())
                if CludesUI and CludesUI.PanelPP then
                    CludesUI.PanelPP.CreateBorder(overlayFrame, 0.898, 0.286, 0.286, 1, 2, "OVERLAY", 1) -- #e54949
                    local enchBdr = CludesUI.PanelPP.GetBorders(overlayFrame)
                    if enchBdr then
                        enchBdr:SetFrameLevel(slotFrame:GetFrameLevel())
                    end
                end
                GetFFD(slotFrame).missingEnchBorder = overlayFrame
            end
            GetFFD(slotFrame).missingEnchBorder:Show()
            missingEnchantSlots[slotFrame] = true
            if not pulseTicker:IsShown() then
                pulseTicker:Show()
            end
        else
            if GetFFD(slotFrame).missingEnchBorder then
                GetFFD(slotFrame).missingEnchBorder:Hide()
            end
            missingEnchantSlots[slotFrame] = nil
            if not next(missingEnchantSlots) then
                pulseTicker:Hide()
            end
        end
    end
    -- Expose so UpdateSlotInfo can drive it from the existing isMissing flag.
    GetFFD(widget).setSlotMissingEnchant = SetSlotMissingEnchant

    -- Repaint borders on inventory/equipment/item-load changes. GetItemInfo can return nil on freshly-linked items; GET_ITEM_INFO_RECEIVED lands the repaint.
    -- The stock styles keep Blizzard's own quality borders: none of this.
    if not mod.CharSheetStock() then
        local inventoryFrame = CreateFrame("Frame")
        -- Registered only while the sheet is open (GET_ITEM_INFO_RECEIVED storms
        -- from bags, loot and the auction house); the open repaint below catches
        -- up anything that changed while it was closed.
        local function WatchInventory(enabled)
            if enabled then
                inventoryFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
                inventoryFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
                inventoryFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
            else
                inventoryFrame:UnregisterAllEvents()
            end
        end
        inventoryFrame:SetScript("OnEvent", function(self, evt, arg1)
            if evt == "UNIT_INVENTORY_CHANGED" and arg1 ~= "player" then
                return
            end
            if not (widget and widget:IsShown()) then
                return
            end
            UpdateSlotBorders()
        end)
        widget:HookScript("OnShow", function()
            WatchInventory(true)
        end)
        widget:HookScript("OnHide", function()
            WatchInventory(false)
        end)
        -- The build runs inside the first OnShow, after that open's hooks fired.
        if widget:IsShown() then
            WatchInventory(true)
        end
        -- Paint once on panel open in case events fired before we hooked up.
        widget:HookScript("OnShow", UpdateSlotBorders)
    end -- not ns.CharSheetStock()

    -- Gem icons inside the slots, and their socket watcher: the CludesUI
    -- sheet only (the stock styles keep Blizzard's own slots untouched).
    -- RefreshAllSocketIcons is read again after the block, hence out here.
    local RefreshAllSocketIcons
    if not mod.CharSheetStock() then
        local globalSocketContainer = CreateFrame("Frame", "CUI_CharSheet_SocketContainer", widget)
        globalSocketContainer:SetFrameLevel(100)
        local isCharacterTab = (widget.selectedTab or 1) == 1
        if isCharacterTab then
            globalSocketContainer:Show()
        else
            globalSocketContainer:Hide()
        end
        GetFFD(widget).socketContainer = globalSocketContainer

        -- Gem layout: gems sit INSIDE the gear icon, anchored bottom-right and stacking
        -- leftward for multiples, inset 2 physical pixels from the slot's 1px border.
        local PP_GEM = CludesUI.PanelPP
        local GEM_PP_MULT = (PP_GEM and PP_GEM.mult) or 1
        local GEM_SIZE = 15
        local GEM_PAD = GEM_PP_MULT -- 1 physical-pixel gap between stacked gems
        local GEM_INSET_X = 2 * GEM_PP_MULT -- 2 physical pixels from slot's right edge
        local GEM_INSET_Y = 2 * GEM_PP_MULT -- 2 physical pixels from slot's bottom edge

        -- Gem border color by rarity: rare+ gold, uncommon silver.
        local function GemBorderColor(quality)
            if (quality or 0) >= 3 then
                return 1.00, 0.82, 0.00, 1 -- gold
            end
            return 0.75, 0.75, 0.75, 1 -- silver
        end

        -- Each socket is a small Frame (not a raw texture) so it can carry a 1px pixel-perfect border.
        local function GetOrCreateSocketIcons(slotFrame, side, slotIndex)
            if GetFFD(slotFrame).charSocketsIcons then
                return GetFFD(slotFrame).charSocketsIcons
            end

            GetFFD(slotFrame).charSocketsIcons = {} -- list of icon textures (gem art)
            GetFFD(slotFrame).charSocketsFrames = {} -- list of parent frames (borders live here)
            GetFFD(slotFrame).charSocketsBtns = GetFFD(slotFrame).charSocketsIcons -- alias for callers
            GetFFD(slotFrame).gemLinks = {}

            for i = 1, 2 do -- max 2 gems displayed per slot
                local gemIcon = CreateFrame("Frame", nil, globalSocketContainer)
                gemIcon:SetSize(GEM_SIZE, GEM_SIZE)
                gemIcon:EnableMouse(true)
                gemIcon:Hide()

                local iconTex = gemIcon:CreateTexture(nil, "ARTWORK")
                iconTex:SetAllPoints(gemIcon)

                -- 2px pixel-perfect border, recolored per-gem in UpdateSocketIcons.
                PP_GEM.CreateBorder(gemIcon, 1, 1, 1, 1, 2, "OVERLAY", 1)
                local gemBdr = PP_GEM.GetBorders(gemIcon)
                if gemBdr then
                    gemBdr:SetFrameLevel(gemIcon:GetFrameLevel())
                end

                GetFFD(slotFrame).charSocketsFrames[i] = gemIcon
                GetFFD(slotFrame).charSocketsIcons[i] = iconTex
            end

            GetFFD(slotFrame).charSocketsSide = side
            GetFFD(slotFrame).charSocketsSlotIndex = slotIndex

            return GetFFD(slotFrame).charSocketsIcons
        end

        local function UpdateSocketIcons(slotKey)
            local slotFrame = _G[slotKey]
            if not slotFrame then
                return
            end

            local slotIndex = slotFrame:GetID()
            local side = tContains(leftColumnSlots, slotKey) and "RIGHT" or "LEFT"

            local socketIcons = GetOrCreateSocketIcons(slotFrame, side, slotIndex)

            local invLink = GetInventoryItemLink("player", slotIndex)
            local gemsEnabled = not (CludesUIDB and CludesUIDB.showGems == false)
            if not invLink or not gemsEnabled then
                for _, gemIcon in ipairs(GetFFD(slotFrame).charSocketsFrames or {}) do
                    gemIcon:Hide()
                end
                return
            end

            local passes = GetFFD(slotFrame).cuiGemPaintPasses or 0
            local socketTextures, totalSockets, nGems, gemLinks = CUI_BuildSocketIconRow(invLink, passes)

            if totalSockets > 0 and nGems == 0 then
                local itemId = GetInventoryItemID("player", slotIndex)
                if itemId and itemId > 0 and C_Item and C_Item.RequestLoadItemDataByID then
                    C_Item.RequestLoadItemDataByID(itemId)
                end
                GetFFD(slotFrame).cuiGemPaintPasses = passes + 1
            else
                GetFFD(slotFrame).cuiGemPaintPasses = 0
            end

            -- TOOLTIP_DATA_UPDATE / GET_ITEM_INFO_RECEIVED drive QueueSocketRefresh until the link's gem bytes match GetItemStats (never scrape a tooltip).

            GetFFD(slotFrame).gemLinks = gemLinks

            -- Position and show gem frames inside the slot's bottom-right, with extra gems stacking leftward.
            if #socketTextures > 0 then
                local gemFrames = GetFFD(slotFrame).charSocketsFrames or {}
                for i, iconTex in ipairs(socketIcons) do
                    local gemIcon = gemFrames[i]
                    if socketTextures[i] and gemIcon then
                        local record = socketTextures[i]
                        if record.isAtlas then
                            -- Empty socket: prefer Blizzard's socket atlas, never a bright
                            -- fallback fill. The inventory link can lack gem bytes while
                            -- GetItemStats still reports sockets, misreading as "missing gem" on gemmed gear.
                            if iconTex.SetAtlas then
                                iconTex:SetAtlas(nil)
                            end
                            iconTex:SetTexture(nil)
                            if iconTex.SetVertexColor then
                                iconTex:SetVertexColor(1, 1, 1, 1)
                            end
                            if iconTex.SetAtlas and record.icon then
                                iconTex:SetColorTexture(0, 0, 0, 0)
                                iconTex:SetAtlas(record.icon)
                            else
                                if iconTex.SetAtlas then
                                    iconTex:SetAtlas(nil)
                                end
                                iconTex:SetColorTexture(0.22, 0.22, 0.26, 0.85)
                            end
                        else
                            -- Clear atlas/color-texture mode before applying a fileID, or the frame
                            -- shows only the PP border after a prior empty-socket atlas paint.
                            if iconTex.SetAtlas then
                                iconTex:SetAtlas(nil)
                            end
                            iconTex:SetColorTexture(0, 0, 0, 0)
                            iconTex:SetTexture(nil)
                            if iconTex.SetVertexColor then
                                iconTex:SetVertexColor(1, 1, 1, 1)
                            end
                            iconTex:SetTexture(record.icon)
                        end

                        gemIcon:ClearAllPoints()
                        gemIcon:SetPoint(
                            "BOTTOMRIGHT",
                            slotFrame,
                            "BOTTOMRIGHT",
                            -GEM_INSET_X,
                            GEM_INSET_Y + (i - 1) * (GEM_SIZE + GEM_PAD)
                        )

                        -- Resolve gem rarity for border color.
                        local gemLink = GetFFD(slotFrame).gemLinks and GetFFD(slotFrame).gemLinks[i]
                        local quality = 2
                        if gemLink then
                            local _, _, region = C_Item.GetItemInfo(gemLink)
                            if region then
                                quality = region
                            end
                        end
                        local region, g, button, a = GemBorderColor(quality)
                        PP_GEM.SetBorderColor(gemIcon, region, g, button, a)

                        gemIcon:Show()

                        gemIcon:SetScript("OnEnter", function(self)
                            if GetFFD(slotFrame).gemLinks[i] then
                                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                                GameTooltip:SetHyperlink(GetFFD(slotFrame).gemLinks[i])
                                GameTooltip:Show()
                            end
                        end)
                        gemIcon:SetScript("OnLeave", function()
                            GameTooltip:Hide()
                        end)
                    elseif gemIcon then
                        gemIcon:Hide()
                    end
                end
            else
                for _, gemIcon in ipairs(GetFFD(slotFrame).charSocketsFrames or {}) do
                    gemIcon:Hide()
                end
            end
        end

        RefreshAllSocketIcons = function()
            for _, slotKey in ipairs(slotList) do
                UpdateSocketIcons(slotKey)
            end
        end
        CludesUI._refreshGemsVisibility = RefreshAllSocketIcons

        -- Hard reset a slot's gem art, called on PLAYER_EQUIPMENT_CHANGED before the debounced
        -- refresh so old gem icons can never linger (e.g. a gemmed ring swapped for an empty-socket one).
        local function ClearSlotGems(slotFrame)
            if not slotFrame then
                return
            end
            GetFFD(slotFrame).cuiGemPaintPasses = 0
            GetFFD(slotFrame).gemLinks = {}
            if GetFFD(slotFrame).charSocketsFrames then
                for _, gemIcon in ipairs(GetFFD(slotFrame).charSocketsFrames) do
                    gemIcon:Hide()
                end
            end
            if GetFFD(slotFrame).charSocketsIcons then
                for _, iconTex in ipairs(GetFFD(slotFrame).charSocketsIcons) do
                    iconTex:SetTexture(nil)
                    if iconTex.SetAtlas then
                        iconTex:SetAtlas(nil)
                    end
                end
            end
        end

        -- Map inventory slot IDs to slot button names, so we can clear the exact changed slot without scanning all 18.
        local _invSlotToName = {}
        for _, slotKey in ipairs(slotList) do
            local button = _G[slotKey]
            if button and button.GetID then
                local ident = button:GetID()
                if ident and ident > 0 then
                    _invSlotToName[ident] = slotKey
                end
            end
        end

        local function CharSheetGemsActive()
            if
                CludesUIDB
                and (CludesUIDB.themedCharacterSheet == false or CludesUI.BlizzWindowSkinsKilled())
            then
                return false
            end
            if CludesUIDB and CludesUIDB.showGems == false then
                return false
            end
            return true
        end

        local _equippedItemIDs = {}
        local function RefreshEquippedItemIDs()
            wipe(_equippedItemIDs)
            for _, slotKey in ipairs(slotList) do
                local sl = _G[slotKey]
                if sl and sl.GetID then
                    local itemId = GetInventoryItemID("player", sl:GetID())
                    if itemId and itemId > 0 then
                        _equippedItemIDs[itemId] = true
                    end
                end
            end
        end
        RefreshEquippedItemIDs()

        -- Equipment/item-load hooks: TRAILING debounce so a burst of GET_ITEM_INFO_RECEIVED
        -- yields one refresh after data settles (a leading debounce fires once on stale links right after /reload).
        local _socketRefreshTimer
        local function QueueSocketRefresh()
            if _socketRefreshTimer then
                _socketRefreshTimer:Cancel()
                _socketRefreshTimer = nil
            end
            _socketRefreshTimer = C_Timer.NewTimer(0.12, function()
                _socketRefreshTimer = nil
                if widget and widget:IsShown() and (widget.selectedTab or 1) == 1 then
                    RefreshAllSocketIcons()
                end
            end)
        end

        local socketWatch = CreateFrame("Frame")
        socketWatch:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        socketWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
        -- Hydration (2 global): must hear item load while Character is closed after
        -- /reload. UNIT_INVENTORY_CHANGED + SOCKET_INFO_UPDATE (2 OnShow-only) below.
        if CharSheetGemsActive() then
            socketWatch:RegisterEvent("TOOLTIP_DATA_UPDATE")
            socketWatch:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        end
        socketWatch:SetScript("OnEvent", function(_, evt, arg1)
            if not CharSheetGemsActive() then
                return
            end
            if evt == "UNIT_INVENTORY_CHANGED" and arg1 ~= "player" then
                return
            end
            if evt == "PLAYER_EQUIPMENT_CHANGED" or evt == "PLAYER_ENTERING_WORLD" then
                RefreshEquippedItemIDs()
            end
            if evt == "GET_ITEM_INFO_RECEIVED" and (not arg1 or not _equippedItemIDs[arg1]) then
                return
            end
            -- Clear the changed slot's stale gem art BEFORE the debounced refresh, or old icons can survive until /reload on cached gem data.
            if evt == "PLAYER_EQUIPMENT_CHANGED" and arg1 then
                local slotKey = _invSlotToName[arg1]
                if slotKey then
                    ClearSlotGems(_G[slotKey])
                end
            end
            -- No refresh work while the sheet is closed (the cache/clear-slot work above still runs).
            if not widget:IsShown() or (widget.selectedTab or 1) ~= 1 then
                return
            end
            QueueSocketRefresh()
        end)

        widget:HookScript("OnShow", function()
            -- Non-hydration high-frequency events: only while the sheet is visible.
            socketWatch:RegisterEvent("UNIT_INVENTORY_CHANGED")
            socketWatch:RegisterEvent("SOCKET_INFO_UPDATE")
            -- Sockets and the container only matter on the Character tab.
            local isCharacterTab = (widget.selectedTab or 1) == 1
            if isCharacterTab then
                RefreshEquippedItemIDs()
                RefreshAllSocketIcons()
                QueueSocketRefresh()
                globalSocketContainer:Show()
            else
                globalSocketContainer:Hide()
            end
        end)

        widget:HookScript("OnHide", function()
            socketWatch:UnregisterEvent("UNIT_INVENTORY_CHANGED")
            socketWatch:UnregisterEvent("SOCKET_INFO_UPDATE")
            if _socketRefreshTimer then
                _socketRefreshTimer:Cancel()
                _socketRefreshTimer = nil
            end
            for _, sn in ipairs(slotList) do
                local sl = _G[sn]
                if sl then
                    GetFFD(sl).cuiGemPaintPasses = 0
                end
            end
            globalSocketContainer:Hide()
            if GetFFD(widget).scrollBar then
                GetFFD(widget).scrollBar:Hide()
            end
        end)
    end -- not ns.CharSheetStock()

    -- Enchant/upgrade-track scanning goes through CUI_ScanInventoryItem
    -- (C_TooltipInfo). NEVER create a scanning tooltip frame from Lua.

    -- Cache item info (ID, level, upgrade track) to update when items change
    local itemCache = {}

    -- Update one slot's item level, enchant and upgrade-track labels. Returns false when
    -- the item's data had not fully arrived (no quality, no item level, or an enchant id
    -- on the link whose name the scan could not read yet), so the caller retries the slot.
    -- An unenchanted item is complete: a missing enchant is an answer, not a failed read.
    local function UpdateSlotInfo(slotKey)
        local slotFrame = _G[slotKey]
        if not slotFrame then
            return true
        end

        -- Tab guard: equipment events fire regardless of the active sub-tab, so
        -- labels must stay hidden if opened straight to Reputation/Currency.
        -- PaperDollFrame:IsShown() is the truth-source; PanelTemplates_GetSelectedTab lags on initial open.
        -- Stock styles: the labels sit on a PaperDollFrame overlay, so Blizzard's
        -- tab code already hides them off the Character tab; gating them here as
        -- well would strand them hidden (no tab hook re-shows them under stock).
        local isCharTab = mod.CharSheetStock() or (PaperDollFrame and PaperDollFrame:IsShown())

        local linkText = GetInventoryItemLink("player", slotFrame:GetID())
        local levelValue = ""
        local enchantText = ""
        local upgradeTrackText = ""
        local upgradeTrackColor = { r = 1, g = 1, b = 1 }
        local itemQuality = nil
        local slotID = slotFrame:GetID()

        if linkText then
            -- GetItemInfo's itemLevel is the cached base level, wrong for upgrade-track
            -- pieces (shows 219 for a 334 item); read the equipped instance instead.
            local _, _, quality = C_Item.GetItemInfo(linkText)
            local itemLvl = GetEquippedItemLevel(slotID)
            levelValue = (itemLvl and itemLvl > 0) and itemLvl or ""
            itemQuality = quality

            -- Enchant via C_TooltipInfo; upgrade track via C_Item (no tooltip).
            enchantText = CUI_GetEnchantText(slotFrame:GetID())
            upgradeTrackText, upgradeTrackColor = CUI_GetUpgradeTrack(linkText)
        end

        -- Item-level display color, resolved once. Shared with the enchant name text when
        -- Enchants is set to Text, so both read in the same color.
        local ilvlColor =
            CludesUI.GetItemLevelColor(linkText, itemQuality, upgradeTrackText, upgradeTrackColor)

        if GetFFD(slotFrame).itemLevelLabel then
            local showItemLevel = (not CludesUIDB) or (CludesUIDB.showItemLevel ~= false)

            if showItemLevel then
                GetFFD(slotFrame).itemLevelLabel:SetText(tostring(levelValue) or "")
                GetFFD(slotFrame).itemLevelLabel:SetShown(isCharTab)
                GetFFD(slotFrame).itemLevelLabel:SetTextColor(ilvlColor.r, ilvlColor.g, ilvlColor.b, 0.9)
            else
                GetFFD(slotFrame).itemLevelLabel:Hide()
            end
        end

        -- Enchant label: keep inline |A:...|a atlas escapes so quality icons render, strip
        -- the readable text, and park the full original text behind a hover tooltip.
        if GetFFD(slotFrame).enchantLabel then
            local showEnchants = (not CludesUIDB) or (CludesUIDB.showEnchants ~= false)
            local iconOnly, tooltipText, isMissing, hasEnchant =
                mod.ParseEnchantLabel(enchantText, slotID, linkText, "player")

            -- Enchants set to Text: render the readable name (item-level colored) instead of the
            -- icon. Missing-enchant warning always keeps its red icon; no-enchant falls back to icon.
            local showNames = CludesUIDB and CludesUIDB.charSheetEnchantNames
            local useName = showNames and hasEnchant and tooltipText and tooltipText ~= ""
            local labelText = useName and tooltipText or iconOnly

            if showEnchants and labelText and labelText ~= "" then
                GetFFD(slotFrame).enchantLabel:SetText(labelText)
                local enchFontSize = (CludesUIDB and CludesUIDB.charSheetEnchantSize) or 9
                if useName then
                    -- Names always render outlined (slug unless Never Show Slug) for legibility over the model.
                    GetFFD(slotFrame).enchantLabel:SetFont(
                        fontFile,
                        enchFontSize,
                        CludesUI.SlugFlag("OUTLINE, SLUG")
                    )
                    -- Item-level color, blended 50% toward white so the name reads
                    -- softer than the ilvl number.
                    GetFFD(slotFrame).enchantLabel:SetTextColor(
                        ilvlColor.r + (1 - ilvlColor.r) * 0.5,
                        ilvlColor.g + (1 - ilvlColor.g) * 0.5,
                        ilvlColor.b + (1 - ilvlColor.b) * 0.5,
                        0.9
                    )
                    -- Cap the name at 45% of the gap between equipment columns (left icons'
                    -- right edge -> right icons' left edge) so a long enchant never bleeds
                    -- over the model or into the far column; overflow ellipsizes, full name
                    -- stays on the tooltip. textOverlayFrame shares the slots' effective scale, so the delta is already in width units.
                    local maxW
                    local leftRef, rightRef = _G.CharacterHeadSlot, _G.CharacterHandsSlot
                    if leftRef and rightRef then
                        local lr, rl = leftRef:GetRight(), rightRef:GetLeft()
                        if lr and rl and rl > lr then
                            maxW = (rl - lr) * 0.45
                        end
                    end
                    GetFFD(slotFrame).enchantLabel:SetWordWrap(false)
                    GetFFD(slotFrame).enchantLabel:SetWidth(maxW or 0)
                else
                    -- Icon mode: no outline (the label's creation default), white
                    -- tint so a prior name-mode color never bleeds onto the atlas
                    -- icons, and clear the width cap.
                    GetFFD(slotFrame).enchantLabel:SetFont(fontFile, enchFontSize, "")
                    GetFFD(slotFrame).enchantLabel:SetTextColor(1, 1, 1, 0.8)
                    GetFFD(slotFrame).enchantLabel:SetWidth(0)
                end
                GetFFD(slotFrame).enchantLabel:SetShown(isCharTab)

                if GetFFD(slotFrame).enchantHoverFrame then
                    GetFFD(slotFrame).enchantHoverFrame:SetShown(isCharTab)
                    GetFFD(slotFrame).enchantHoverFrame:SetScript("OnEnter", function(self)
                        if not tooltipText or tooltipText == "" then
                            return
                        end
                        CludesUI.ShowWidgetTooltip(self, tooltipText)
                    end)
                    GetFFD(slotFrame).enchantHoverFrame:SetScript("OnLeave", function()
                        CludesUI.HideWidgetTooltip()
                    end)
                end
            else
                GetFFD(slotFrame).enchantLabel:Hide()
                if GetFFD(slotFrame).enchantHoverFrame then
                    GetFFD(slotFrame).enchantHoverFrame:Hide()
                end
            end

            -- Pulsing red border for missing enchants, driven by the same isMissing
            -- flag so it stays in sync with the icon swap.
            if GetFFD(widget).setSlotMissingEnchant then
                GetFFD(widget).setSlotMissingEnchant(slotFrame, isMissing == true)
            end
        end

        if GetFFD(slotFrame).upgradeTrackLabel then
            local showUpgradeTrack = (not CludesUIDB) or (CludesUIDB.showUpgradeTrack ~= false)

            if showUpgradeTrack then
                GetFFD(slotFrame).upgradeTrackLabel:SetText(
                    upgradeTrackText ~= "" and ("(" .. upgradeTrackText .. ")") or ""
                )
                GetFFD(slotFrame).upgradeTrackLabel:SetShown(isCharTab)

                local displayColor
                if
                    CludesUIDB
                    and CludesUIDB.charSheetUpgradeTrackUseColor
                    and CludesUIDB.charSheetUpgradeTrackColor
                then
                    displayColor = CludesUIDB.charSheetUpgradeTrackColor
                else
                    -- Track's own rarity color by default.
                    displayColor = upgradeTrackColor
                end

                GetFFD(slotFrame).upgradeTrackLabel:SetTextColor(
                    displayColor.r,
                    displayColor.g,
                    displayColor.b,
                    0.8
                )
            else
                GetFFD(slotFrame).upgradeTrackLabel:Hide()
            end
        end

        -- Stat letters (off unless true; the tertiaries only when their own key
        -- is true too). Not on the shirt or tabard, nor on WoW Forever, whose
        -- sheet has its own stat text and no options row.
        local lettersPending = false
        local wantLetters = linkText
            and not CludesUI.IS_FOREVER
            and CludesUIDB
            and CludesUIDB.charSheetItemStats == true
            and slotKey ~= "CharacterShirtSlot"
            and slotKey ~= "CharacterTabardSlot"
        local statCaption, terLabel = GetFFD(slotFrame).statLetterLabel, GetFFD(slotFrame).statLetterTerLabel
        if wantLetters and not statCaption then
            statCaption, terLabel = GetFFD(widget).statLetterLabels(slotFrame)
        end
        if statCaption then
            -- Keep the letters' frame above the slot icon: the slots' strata
            -- and level can differ from the overlay's (and change after the
            -- build), and the icon would otherwise draw over the text.
            local letterFrame = statCaption:GetParent()
            if letterFrame:GetFrameStrata() ~= slotFrame:GetFrameStrata() then
                letterFrame:SetFrameStrata(slotFrame:GetFrameStrata())
            end
            if letterFrame:GetFrameLevel() <= slotFrame:GetFrameLevel() + 5 then
                letterFrame:SetFrameLevel(math.max(100, slotFrame:GetFrameLevel()) + 10)
            end
            lettersPending = CludesUI.PaintStatLetterRows(
                statCaption,
                terLabel,
                wantLetters and linkText or nil,
                CludesUIDB and CludesUIDB.charSheetItemStatsTertiary == true
            )
            statCaption:SetShown(isCharTab)
            terLabel:SetShown(isCharTab)
        end

        if not linkText then
            return true
        end
        local enchantID = tonumber(linkText:match("item:%d+:(%d+)"))
        local enchantPending = enchantID and enchantID ~= 0 and enchantText == ""
        return itemQuality ~= nil and levelValue ~= "" and not enchantPending and not lettersPending
    end

    -- Slots whose last read came back incomplete (item or tooltip data still on
    -- the way): waitLink holds the item each waits on, waitSince when that wait
    -- began this open. They sit in itemCache as false, never the link (an
    -- emptied slot must still compare unequal), so the next refresh reads them
    -- again; item-data events refresh only while one waits. A read still
    -- incomplete MAX_WAIT seconds into its wait stays as it is until the sheet
    -- opens again (rereadOnShow). The wait is bounded by time, not by reads, so
    -- passes that are not its data (a tooltip storm, an equipment-set swap)
    -- never use it up.
    local waitLink, waitSince, rereadOnShow = {}, {}, {}
    local MAX_WAIT = 5

    -- Event-driven per-slot label refresh; item-link cache guards redundant work, events catch upgrade/enchant/socket changes without polling.
    local function RefreshAllSlotLabels()
        if CludesUIDB and (CludesUIDB.themedCharacterSheet == false or CludesUI.BlizzWindowSkinsKilled()) then
            return
        end
        if not (widget and widget:IsShown()) then
            return
        end
        local nowTime
        for _, slotKey in ipairs(slotList) do
            local linkText = GetInventoryItemLink("player", _G[slotKey]:GetID())
            if itemCache[slotKey] ~= linkText then
                if UpdateSlotInfo(slotKey) then
                    rereadOnShow[slotKey] = nil
                    itemCache[slotKey], waitLink[slotKey], waitSince[slotKey] = linkText, nil, nil
                else
                    nowTime = nowTime or GetTime()
                    local since = waitLink[slotKey] == linkText and waitSince[slotKey] or nowTime
                    if nowTime - since < MAX_WAIT then
                        itemCache[slotKey], waitLink[slotKey], waitSince[slotKey] = false, linkText, since
                    else
                        rereadOnShow[slotKey] = true
                        itemCache[slotKey], waitLink[slotKey], waitSince[slotKey] = linkText, nil, nil
                    end
                end
            end
        end
    end

    -- True while a slot waits on the item GET_ITEM_INFO_RECEIVED reported.
    local function WaitsOnItem(itemId)
        for slotKey in pairs(waitLink) do
            if GetInventoryItemID("player", _G[slotKey]:GetID()) == itemId then
                return true
            end
        end
        return false
    end

    -- Public: force a full slot-label rebuild with no item change. Render-only settings (e.g.
    -- the Enchants mode) leave items untouched, so the item-link cache above would short-circuit every slot and never apply live.
    -- Every slot is marked unread (false), empty ones included: a slot emptied
    -- while the sheet was closed must still be read on the next open.
    function CludesUI._refreshCharSheetSlotLabels()
        for _, slotKey in ipairs(slotList) do
            itemCache[slotKey] = false
        end
        RefreshAllSlotLabels()
    end

    if not GetFFD(widget).itemLevelMonitor then
        local watcher = CreateFrame("Frame")
        GetFFD(widget).itemLevelMonitor = watcher
        -- No BAG_UPDATE_DELAYED: bag contents cannot change the displayed
        -- equipped-item info (ilvl / enchant / upgrade track). Registered only
        -- while the sheet is open; the OnShow pass catches up on the rest.
        local function watch(enabled)
            if enabled then
                watcher:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
                watcher:RegisterEvent("UNIT_INVENTORY_CHANGED")
                watcher:RegisterEvent("SOCKET_INFO_UPDATE")
                watcher:RegisterEvent("ITEM_UPGRADE_MASTER_UPDATE")
                -- Item/tooltip data arriving late for a slot whose read came back
                -- incomplete. Both storm in cities, so the handler drops them at once
                -- while no slot waits (and an item that no slot waits on) and
                -- debounces the rest.
                watcher:RegisterEvent("GET_ITEM_INFO_RECEIVED")
                watcher:RegisterEvent("TOOLTIP_DATA_UPDATE")
            else
                watcher:UnregisterAllEvents()
            end
        end
        local retryTimer
        -- The equipment events storm (a set swap fires one per changed slot):
        -- one pass on the next frame for the whole burst, on a frame shown only
        -- while that pass is pending.
        local flushFn = CreateFrame("Frame")
        flushFn:Hide()
        flushFn:SetScript("OnUpdate", function(self)
            self:Hide()
            RefreshAllSlotLabels()
        end)
        watcher:SetScript("OnEvent", function(_, evt, arg1)
            if evt == "GET_ITEM_INFO_RECEIVED" or evt == "TOOLTIP_DATA_UPDATE" then
                if retryTimer or not next(waitLink) then
                    return
                end
                if evt == "GET_ITEM_INFO_RECEIVED" and not WaitsOnItem(arg1) then
                    return
                end
                retryTimer = C_Timer.NewTimer(0.12, function()
                    retryTimer = nil
                    RefreshAllSlotLabels()
                end)
                return
            end
            if evt == "UNIT_INVENTORY_CHANGED" and arg1 ~= "player" then
                return
            end
            if not (widget and widget:IsShown()) then
                return
            end
            flushFn:Show()
        end)
        widget:HookScript("OnShow", function()
            watch(true)
        end)
        widget:HookScript("OnHide", function()
            watch(false)
        end)
        watch(widget:IsShown())
        -- Each open gives every slot still waiting a fresh wait, and reads
        -- again the slots whose wait ran out.
        widget:HookScript("OnShow", function()
            wipe(waitSince)
            for slotKey in pairs(rereadOnShow) do
                itemCache[slotKey], rereadOnShow[slotKey] = false, nil
            end
            RefreshAllSlotLabels()
        end)
        -- Skinning is deferred to first open, so the hook above is installed
        -- mid-show and misses this open event; refresh now to decorate it.
        RefreshAllSlotLabels()
    end

    -- Same deferred-skin timing for gem icons: the OnShow hook above is installed
    -- mid-show and won't fire for the first open.
    if RefreshAllSocketIcons and (widget.selectedTab or 1) == 1 then
        RefreshAllSocketIcons()
    end

    -- Re-apply tab visibility now that every element exists: the earlier call runs before the
    -- stats panel/model scene/slots are created, so opening Rep/Currency by hotkey would leave character-tab elements visible.
    local isCharTab = not (_G.ReputationFrame and _G.ReputationFrame:IsShown())
        and not (_G.TokenFrame and _G.TokenFrame:IsShown())
    ApplyTabVisibility(isCharTab)
end

-- Fake bottom tab on the character sheet, visually identical to the Blizzard
-- Character/Rep/Currency tabs. Built on first enable only (zero cost while off).
local function EnsureCalcTab(widget)
    local existing = GetFFD(widget).calcToggleBtn
    if existing then
        return existing
    end

    local fontFile = CludesUI.GetFontPath("blizzardSkin") or STANDARD_TEXT_FONT
    local Pix = CludesUI and CludesUI.PP

    local refTab = _G["CharacterFrameTab1"]
    local tabW = refTab and refTab:GetWidth() or 80
    local tabH = refTab and refTab:GetHeight() or 32

    local calcTabBtn = CreateFrame("Button", "CUI_CharSheet_CalcTab", widget)
    calcTabBtn:SetSize(tabW, tabH)
    calcTabBtn:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -10, -30)
    calcTabBtn:SetFrameLevel(widget:GetFrameLevel() + 5)
    calcTabBtn:EnableMouse(true)

    local backdrop = calcTabBtn:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(0.068, 0.056, 0.052, 1)

    local activeHighlight = calcTabBtn:CreateTexture(nil, "ARTWORK", nil, -6)
    activeHighlight:SetAllPoints()
    activeHighlight:SetColorTexture(1, 1, 1, 0.02)
    activeHighlight:SetBlendMode("ADD")
    activeHighlight:Hide()

    local caption = calcTabBtn:CreateFontString(nil, "OVERLAY")
    caption:SetFont(fontFile, 9, "")
    caption:SetPoint("CENTER", calcTabBtn, "CENTER", 0, 0)
    caption:SetJustifyH("CENTER")
    caption:SetText("Upgrades")

    local ACC = CludesUI.CLUDES_GREEN or { r = 0.30, g = 0.79, b = 0.94 }
    local underlineTex = calcTabBtn:CreateTexture(nil, "OVERLAY", nil, 6)
    if Pix and Pix.DisablePixelSnap then
        Pix.DisablePixelSnap(underlineTex)
        underlineTex:SetHeight(Pix.mult or 1)
    else
        underlineTex:SetHeight(1)
    end
    underlineTex:SetPoint("BOTTOMLEFT", calcTabBtn, "BOTTOMLEFT", 0, 0)
    underlineTex:SetPoint("BOTTOMRIGHT", calcTabBtn, "BOTTOMRIGHT", 0, 0)
    underlineTex:SetColorTexture(ACC.r, ACC.g, ACC.b, 1)
    underlineTex:Hide()
    CludesUI.RegAccent({ type = "solid", obj = underlineTex, a = 1 })

    local function RefreshCalcTab()
        local found = _G["CUIUpgCalcFrame"]
        if found and not GetFFD(calcTabBtn)._calcHooked then
            GetFFD(calcTabBtn)._calcHooked = true
            found:HookScript("OnShow", RefreshCalcTab)
            found:HookScript("OnHide", RefreshCalcTab)
        end
        local isOpen = found and found:IsShown()
        caption:SetTextColor(1, 1, 1, isOpen and 1 or 0.5)
        underlineTex:SetShown(isOpen)
        activeHighlight:SetShown(isOpen)
    end
    RefreshCalcTab()

    calcTabBtn:SetScript("OnEnter", function()
        caption:SetTextColor(1, 1, 1, 1)
    end)
    calcTabBtn:SetScript("OnLeave", function()
        RefreshCalcTab()
    end)
    calcTabBtn:SetScript("OnClick", function()
        local found = _G["CUIUpgCalcFrame"]
        if found then
            if found:IsShown() then
                found:Hide()
            else
                found:Show()
            end
            RefreshCalcTab()
        end
    end)

    widget:HookScript("OnShow", RefreshCalcTab)
    GetFFD(widget).calcToggleBtn = calcTabBtn
    GetFFD(widget).updateCalcBtnColor = RefreshCalcTab
    return calcTabBtn
end

-- Show/hide the Upgrades calc tab from upgradeCalcOpts.showCalcButton (live toggle).
local function ApplyCharSheetCalcTab()
    -- Part of the retail makeover: nothing to hang it on under WoW Forever.
    if CludesUI.IS_FOREVER then
        return
    end
    if not CharacterFrame then
        return
    end
    if not skinned then
        return
    end
    if CludesUIDB and (CludesUIDB.themedCharacterSheet == false or CludesUI.BlizzWindowSkinsKilled()) then
        return
    end
    -- The stock styles keep Blizzard's own bottom tab row.
    if mod.CharSheetStock() then
        return
    end
    local show = false
    if CUIUpgCalc and CUIUpgCalc.GetOptsDB then
        local calcDb = CUIUpgCalc.GetOptsDB()
        show = calcDb and calcDb.showCalcButton or false
    end
    if show then
        EnsureCalcTab(CharacterFrame):SetShown(true)
    else
        local calcTabBtn = GetFFD(CharacterFrame).calcToggleBtn
        if calcTabBtn then
            calcTabBtn:SetShown(false)
        end
    end
end

-- Blizzard shows these popout buttons on the Equipment tab. Alpha only hides
-- their artwork; native click handlers and modified-hover flyouts stay intact.
-- Show/Hide and arrow reversal do not reset alpha, so no hooks are needed.
local slotFlyoutArrowsHidden = false
function CludesUI._refreshCharSheetSlotFlyoutArrows()
    local hide = not CludesUI.IS_FOREVER
        and CludesUIDB
        and CludesUIDB.charSheetHideSlotFlyoutArrows == true
        and CludesUIDB.themedCharacterSheet ~= false
        and not CludesUI.BlizzWindowSkinsKilled()
    if not hide and not slotFlyoutArrowsHidden then
        return
    end

    for _, slotKey in ipairs(CUI_ALL_SLOTS) do
        local slotFrame = _G[slotKey]
        local btnFrame = slotFrame and slotFrame.popoutButton
        if btnFrame then
            if hide then
                local payload = GetFFD(btnFrame)
                if payload.slotFlyoutAlpha == nil then
                    payload.slotFlyoutAlpha = btnFrame:GetAlpha()
                end
                btnFrame:SetAlpha(0)
            else
                local payload = FFD[btnFrame]
                if payload and payload.slotFlyoutAlpha ~= nil then
                    btnFrame:SetAlpha(payload.slotFlyoutAlpha)
                    payload.slotFlyoutAlpha = nil
                end
            end
        end
    end
    slotFlyoutArrowsHidden = hide
end

-- Gear flyout (hover/click a slot -> popup of same-slot items) in the
-- CludesUI sheet's look: Blizzard's parchment strips and paging bar give
-- way to a flat panel, the item icons are squared with a square rarity edge,
-- and the gold glow around the source slot (sized for Blizzard's slot art) is
-- dropped. A post-hook on EquipmentFlyout_UpdateItems, so it re-applies after
-- every fill (Blizzard re-shows and re-sizes its strips each time). Regions
-- only, plus child frames: no key is ever written onto a flyout button, and
-- the rarity edge takes an explicit colour read off Blizzard's ring, so no
-- method hook lands on the buttons either.
do
    local function FlyoutSkinActive()
        if CludesUI.IS_FOREVER or mod.CharSheetStock() then
            return false
        end
        return not (
            CludesUIDB
            and (CludesUIDB.themedCharacterSheet == false or CludesUI.BlizzWindowSkinsKilled())
        )
    end

    local function SkinFlyoutButton(btnFrame)
        if not btnFrame or btnFrame:IsForbidden() then
            return
        end
        local Skin = mod.WSkin
        local skinData = GetFFD(btnFrame)
        if not skinData.cuiFlyoutSkinned then
            skinData.cuiFlyoutSkinned = true
            local nt = btnFrame.GetNormalTexture and btnFrame:GetNormalTexture()
            if nt then
                nt:SetAlpha(0)
            end
            if btnFrame.icon then
                Skin.SquareIcon(btnFrame.icon)
            end
        end
        -- The ring is Blizzard's quality cue, rounded: hidden by alpha, its
        -- colour carried over to the square edge on every fill.
        local ring = btnFrame.IconBorder
        if ring then
            ring:SetAlpha(0)
        end
        if btnFrame.icon then
            local region, g, button = Skin.RingQuality(ring)
            Skin.QualityBorder(btnFrame, btnFrame.icon, region or 0, g or 0, button or 0)
        end
    end

    local function SkinFlyout()
        if not FlyoutSkinActive() then
            return
        end
        local Skin = mod.WSkin
        local flyout = _G.EquipmentFlyoutFrame
        if not (Skin and flyout) then
            return
        end
        if flyout.Highlight then
            flyout.Highlight:SetAlpha(0)
        end

        local anchorFrame = flyout.buttonFrame
        if anchorFrame then
            -- Panel fades the strips it finds now; Blizzard adds more (bgN)
            -- as the flyout grows, so every strip is faded on every fill.
            Skin.Panel(anchorFrame)
            for i = 1, anchorFrame.numBGs or 0 do
                local strip = anchorFrame["bg" .. i]
                if strip then
                    strip:SetAlpha(0)
                end
            end
        end

        local nav = flyout.NavigationFrame
        if nav and not GetFFD(nav).cuiFlyoutSkinned then
            GetFFD(nav).cuiFlyoutSkinned = true
            Skin.Panel(nav)
            if nav.PrevButton then
                Skin.PageButton(nav.PrevButton, "<", 12)
            end
            if nav.NextButton then
                Skin.PageButton(nav.NextButton, ">", 12)
            end
            for _, regionFrame in ipairs({ nav:GetRegions() }) do
                if regionFrame:IsObjectType("FontString") then
                    Skin.Font(regionFrame)
                end
            end
        end

        for _, btnFrame in ipairs(flyout.buttons or {}) do
            if btnFrame:IsShown() then
                SkinFlyoutButton(btnFrame)
            end
        end
    end

    local hooked = false
    function CludesUI._installEquipmentFlyoutSkin()
        if hooked or not _G.EquipmentFlyout_UpdateItems then
            return
        end
        hooked = true
        hooksecurefunc("EquipmentFlyout_UpdateItems", SkinFlyout)
    end
end

-- Entry point: apply the themed character sheet.
local function ApplyThemedCharacterSheet()
    -- WoW Forever: the full makeover stands down; the CludesUI look and
    -- Blizz Default's slot text there are
    -- CludesUIBlizzardSkin_CharacterSheetForever.lua.
    if CludesUI.IS_FOREVER then
        return
    end
    if CludesUIDB and (CludesUIDB.themedCharacterSheet == false or CludesUI.BlizzWindowSkinsKilled()) then
        return
    end

    if CharacterFrame then
        SkinCharacterSheet()
    end
end

if CludesUI then
    CludesUI.ApplyThemedCharacterSheet = ApplyThemedCharacterSheet
    CludesUI.ApplyCharSheetCalcTab = ApplyCharSheetCalcTab

    -- Setup at PLAYER_LOGIN to register drag hooks early
    local initFrame = CreateFrame("Frame")
    initFrame:RegisterEvent("PLAYER_LOGIN")
    initFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        -- WoW Forever: none of this (pre-skin, portrait suppression, the
        -- makeover, the equipment-set watcher) runs; see the Forever file.
        if CludesUI.IS_FOREVER then
            return
        end
        if CharacterFrame then
            CludesUI._refreshCharSheetSlotFlyoutArrows()
            CludesUI._installEquipmentFlyoutSkin()
            -- Pre-skin runs early, while CharacterFrame is still hidden; running it
            -- mid-OnShow breaks the Rep/Currency ScrollBox data render.
            local sheetOn = not CludesUIDB
                or (CludesUIDB.themedCharacterSheet ~= false and not CludesUI.BlizzWindowSkinsKilled())
            if sheetOn and mod.CharSheetStock() then
                -- Stock styles: Blizzard's frame stays as it is. The one write is
                -- parking Blizzard's stats pane off-screen (method calls, never
                -- Hide) so the CludesUI stats section, a child of the pane
                -- anchored over its InsetRight slot, replaces its list while the
                -- pane's own Show/Hide keeps driving visibility. Done here, while
                -- the frame is hidden, for the same Rep/Currency reason.
                mod.CharSheetParkStatsPane()
            elseif sheetOn then
                PreSkinCharacterSheet()
                -- PreSkin hides the portrait once; Blizzard's CharacterFrameMixin:UpdatePortrait
                -- (RefreshDisplay/UNIT_PORTRAIT_UPDATE/spec icon) runs after OnShow hooks and redraws it -- re-hide via secure hook + deferred GetPortrait() passes too.
                if not GetFFD(CharacterFrame)._cuiPortraitSuppressRegistered then
                    local function SuppressCharacterFramePortrait()
                        if
                            CludesUIDB
                            and (
                                CludesUIDB.themedCharacterSheet == false or CludesUI.BlizzWindowSkinsKilled()
                            )
                        then
                            return
                        end
                        if not CharacterFrame then
                            return
                        end
                        -- Blizzard re-anchors CharacterFrameInsetRight (parent of PaperDollSidebarTabs,
                        -- Tab1 = circular player/spec portrait) on each open; re-park it off-screen as PreSkin does.
                        local inset = _G.CharacterFrameInsetRight
                        if inset then
                            if inset.NineSlice then
                                inset.NineSlice:Hide()
                            end
                            inset:ClearAllPoints()
                            inset:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 10000, -10000)
                        end
                        if CharacterFrame.Portrait then
                            CharacterFrame.Portrait:SetShown(false)
                            CharacterFrame.Portrait:SetAlpha(0)
                        end
                        local named = _G.CharacterFramePortrait
                        if named then
                            named:SetShown(false)
                            named:SetAlpha(0)
                            if named.EnableMouse then
                                named:EnableMouse(false)
                            end
                        end
                        if CharacterFrame.GetPortrait then
                            local texture = CharacterFrame:GetPortrait()
                            if texture then
                                if texture.SetShown then
                                    texture:SetShown(false)
                                end
                                if texture.SetAlpha then
                                    texture:SetAlpha(0)
                                end
                            end
                        end
                    end

                    local function RegisterPortraitSuppression()
                        if not CharacterFrame or not CharacterFrame.UpdatePortrait then
                            return false
                        end
                        if GetFFD(CharacterFrame)._cuiPortraitSuppressRegistered then
                            return true
                        end
                        GetFFD(CharacterFrame)._cuiPortraitSuppressRegistered = true

                        CharacterFrame:HookScript("OnShow", function()
                            SuppressCharacterFramePortrait()
                            C_Timer.After(0, SuppressCharacterFramePortrait)
                            C_Timer.After(0.05, SuppressCharacterFramePortrait)
                        end)

                        hooksecurefunc(CharacterFrame, "UpdatePortrait", function()
                            if
                                CludesUIDB
                                and (
                                    CludesUIDB.themedCharacterSheet == false
                                    or CludesUI.BlizzWindowSkinsKilled()
                                )
                            then
                                return
                            end
                            SuppressCharacterFramePortrait()
                        end)

                        if CharacterFrame.RefreshDisplay then
                            hooksecurefunc(CharacterFrame, "RefreshDisplay", function()
                                if
                                    CludesUIDB
                                    and (
                                        CludesUIDB.themedCharacterSheet == false
                                        or CludesUI.BlizzWindowSkinsKilled()
                                    )
                                then
                                    return
                                end
                                SuppressCharacterFramePortrait()
                            end)
                        end

                        if CharacterFrame.SetPortraitToSpecIcon then
                            hooksecurefunc(CharacterFrame, "SetPortraitToSpecIcon", function()
                                if
                                    CludesUIDB
                                    and (
                                        CludesUIDB.themedCharacterSheet == false
                                        or CludesUI.BlizzWindowSkinsKilled()
                                    )
                                then
                                    return
                                end
                                SuppressCharacterFramePortrait()
                            end)
                        end

                        local portrait = _G.CharacterFramePortrait
                        if portrait then
                            portrait:HookScript("OnShow", function(self)
                                if
                                    CludesUIDB
                                    and (
                                        CludesUIDB.themedCharacterSheet == false
                                        or CludesUI.BlizzWindowSkinsKilled()
                                    )
                                then
                                    return
                                end
                                self:SetShown(false)
                                self:SetAlpha(0)
                            end)
                        end

                        SuppressCharacterFramePortrait()
                        return true
                    end

                    if not RegisterPortraitSuppression() then
                        local tries = 0
                        local ticker
                        ticker = C_Timer.NewTicker(0.25, function()
                            tries = tries + 1
                            if RegisterPortraitSuppression() or tries >= 40 then
                                ticker:Cancel()
                            end
                        end)
                    end
                end
            end

            -- Heavy skin (model, slots, stats, tabs) defers to first OnShow.
            CharacterFrame:HookScript("OnShow", ApplyThemedCharacterSheet)

            -- Auto-equip equipment set when spec changes
            local specChangeFrame = CreateFrame("Frame")
            local lastSpecIndex = GetSpecialization()
            specChangeFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
            specChangeFrame:SetScript("OnEvent", function()
                -- Auto-equip when spec actually changes (not just event noise)
                local currentSpecIndex = GetSpecialization()
                if currentSpecIndex ~= lastSpecIndex then
                    lastSpecIndex = currentSpecIndex
                    local setIDs = C_EquipmentSet.GetEquipmentSetIDs()
                    if setIDs then
                        for _, setID in ipairs(setIDs) do
                            local assignedSpec = C_EquipmentSet.GetEquipmentSetAssignedSpec(setID)
                            if assignedSpec and assignedSpec == currentSpecIndex then
                                CUI_EquipSet(setID)
                                break
                            end
                        end
                    end
                end
            end)
        end
    end)
end

-- Apply the char-sheet label size / outline / shadow settings.
function CludesUI._applyCharSheetTextSizes()
    if not CharacterFrame then
        return
    end

    local itemLevelSize = CludesUIDB and CludesUIDB.charSheetItemLevelSize or 11
    local upgradeTrackSize = CludesUIDB and CludesUIDB.charSheetUpgradeTrackSize or 11
    local enchantSize = CludesUIDB and CludesUIDB.charSheetEnchantSize or 9

    local itemLevelShadow = CludesUIDB and CludesUIDB.charSheetItemLevelShadow or false
    local itemLevelOutline = CludesUIDB and CludesUIDB.charSheetItemLevelOutline or false
    local upgradeTrackShadow = CludesUIDB and CludesUIDB.charSheetUpgradeTrackShadow or false
    local upgradeTrackOutline = CludesUIDB and CludesUIDB.charSheetUpgradeTrackOutline or false
    local enchantShadow = CludesUIDB and CludesUIDB.charSheetEnchantShadow or false
    local enchantOutline = CludesUIDB and CludesUIDB.charSheetEnchantOutline or false

    local fontFile = CludesUI.GetFontPath("blizzardSkin") or STANDARD_TEXT_FONT

    local slotList = CUI_GEAR_SLOTS

    for _, slotKey in ipairs(slotList) do
        local slotFrame = _G[slotKey]
        if slotFrame then
            if GetFFD(slotFrame).itemLevelLabel then
                local flags = ""
                if itemLevelOutline then
                    flags = CludesUI.SlugFlag("OUTLINE, SLUG")
                end
                CludesUI.PrimeFontShadow(GetFFD(slotFrame).itemLevelLabel, itemLevelShadow)
                GetFFD(slotFrame).itemLevelLabel:SetFont(fontFile, itemLevelSize, flags)
            end
            if GetFFD(slotFrame).upgradeTrackLabel then
                local flags = ""
                if upgradeTrackOutline then
                    flags = CludesUI.SlugFlag("OUTLINE, SLUG")
                end
                CludesUI.PrimeFontShadow(GetFFD(slotFrame).upgradeTrackLabel, upgradeTrackShadow)
                GetFFD(slotFrame).upgradeTrackLabel:SetFont(fontFile, upgradeTrackSize, flags)
            end
            if GetFFD(slotFrame).enchantLabel then
                local flags = ""
                if enchantOutline then
                    flags = CludesUI.SlugFlag("OUTLINE, SLUG")
                end
                CludesUI.PrimeFontShadow(GetFFD(slotFrame).enchantLabel, enchantShadow)
                GetFFD(slotFrame).enchantLabel:SetFont(fontFile, enchantSize, flags)
            end
        end
    end
end

function CludesUI._refreshCharacterSheetColors()
    local charFrame = CharacterFrame
    if not charFrame or not GetFFD(charFrame).statsSections then
        return
    end

    -- Default category colors
    local DEFAULT_CATEGORY_COLORS = {
        Attributes = { r = 0.298, g = 0.788, b = 0.941 },
        ["Secondary Stats"] = { r = 0.471, g = 0.255, b = 0.784 },
        ["Tertiary Stats"] = { r = 0.859, g = 0.325, b = 0.855 },
        Attack = { r = 1, g = 0.353, b = 0.122 },
        Defense = { r = 0.247, g = 0.655, b = 1 },
        Crests = { r = 1, g = 0.784, b = 0.341 },
        PvP = { r = 0.671, g = 0.431, b = 0.349 },
    }

    local function GetCategoryColor(titleText)
        local blizz = mod.CharSheetBlizzColor()
        if blizz then
            return blizz
        end
        local useCustom = CludesUIDB
            and CludesUIDB.statCategoryUseColor
            and CludesUIDB.statCategoryUseColor[titleText]
        if useCustom then
            local custom = CludesUIDB
                and CludesUIDB.statCategoryColors
                and CludesUIDB.statCategoryColors[titleText]
            if custom then
                return custom
            end
        end
        return DEFAULT_CATEGORY_COLORS[titleText] or { r = 1, g = 1, b = 1 }
    end

    -- Stock styles' "Blizzard UI Color": titles in Blizzard's yellow, values in
    -- the label grey (nil under the CludesUI look or with the toggle off).
    local blizzYellow = mod.CharSheetBlizzColor()

    -- Recolor each section by its persisted colorKey (DB key), not display title, so mismatches like "Secondary" vs "Secondary Stats" resolve correctly.
    for _, sectionInfo in ipairs(GetFFD(charFrame).statsSections) do
        local key = sectionInfo.colorKey or sectionInfo.sectionTitle
        local pickedColor = GetCategoryColor(key)

        if sectionInfo.titleFS then
            sectionInfo.titleFS:SetTextColor(pickedColor.r, pickedColor.g, pickedColor.b, 1)
        end
        if sectionInfo.leftBar then
            sectionInfo.leftBar:SetColorTexture(pickedColor.r, pickedColor.g, pickedColor.b, 0.8)
        end
        if sectionInfo.rightBar then
            sectionInfo.rightBar:SetColorTexture(pickedColor.r, pickedColor.g, pickedColor.b, 0.8)
        end
        if sectionInfo.upIcon then
            sectionInfo.upIcon:SetVertexColor(pickedColor.r, pickedColor.g, pickedColor.b, 1)
        end
        if sectionInfo.downIcon then
            sectionInfo.downIcon:SetVertexColor(pickedColor.r, pickedColor.g, pickedColor.b, 1)
        end
        for _, statRow in ipairs(sectionInfo.stats) do
            if statRow.value then
                if blizzYellow then
                    statRow.value:SetTextColor(0.7, 0.7, 0.7, 0.8)
                else
                    statRow.value:SetTextColor(pickedColor.r, pickedColor.g, pickedColor.b, 1)
                end
            end
        end
    end

    -- The item level follows the same toggle (Blizzard's yellow, else our purple).
    local itemLvl = GetFFD(charFrame).iLvlText
    if itemLvl then
        if blizzYellow then
            itemLvl:SetTextColor(blizzYellow.r, blizzYellow.g, blizzYellow.b, 1)
        else
            itemLvl:SetTextColor(0.6, 0.2, 1, 1)
        end
    end
end

-- Re-apply the equipment-icon crop when Icon Zoom changes (texcoord persists across item swaps, so only slider changes need this).
function CludesUI._refreshCharSheetIconZoom()
    -- Only the themed sheet crops its slot icons; if off, slots show Blizzard's default icons, which we must not re-crop.
    if CludesUIDB and (CludesUIDB.themedCharacterSheet == false or CludesUI.BlizzWindowSkinsKilled()) then
        return
    end
    -- Same for the stock styles: Blizzard's own slots (the inspect sheet reads the setting itself).
    if mod.CharSheetStock() then
        return
    end
    local z = (CludesUIDB and CludesUIDB.charSheetIconZoom) or 0.07
    for _, slotKey in ipairs(CUI_ALL_SLOTS) do
        local slotFrame = _G[slotKey]
        if slotFrame and slotFrame.icon then
            slotFrame.icon:SetTexCoord(z, 1 - z, z, 1 - z)
        end
    end
end

function CludesUI._refreshUpgradeTrackVisibility()
    local slotList = CUI_GEAR_SLOTS

    local showUpgradeTrack = (not CludesUIDB) or (CludesUIDB.showUpgradeTrack ~= false)

    for _, slotKey in ipairs(slotList) do
        local slotFrame = _G[slotKey]
        if slotFrame and GetFFD(slotFrame).upgradeTrackLabel then
            if showUpgradeTrack then
                GetFFD(slotFrame).upgradeTrackLabel:Show()
            else
                GetFFD(slotFrame).upgradeTrackLabel:Hide()
            end
        end
    end
end

function CludesUI._refreshEnchantsVisibility()
    local slotList = CUI_GEAR_SLOTS

    local showEnchants = (not CludesUIDB) or (CludesUIDB.showEnchants ~= false)

    for _, slotKey in ipairs(slotList) do
        local slotFrame = _G[slotKey]
        if slotFrame and GetFFD(slotFrame).enchantLabel then
            if showEnchants then
                GetFFD(slotFrame).enchantLabel:Show()
                if GetFFD(slotFrame).enchantHoverFrame then
                    GetFFD(slotFrame).enchantHoverFrame:Show()
                end
            else
                GetFFD(slotFrame).enchantLabel:Hide()
                if GetFFD(slotFrame).enchantHoverFrame then
                    GetFFD(slotFrame).enchantHoverFrame:Hide()
                end
            end
        end
    end
end

function CludesUI._refreshItemLevelVisibility()
    local slotList = CUI_GEAR_SLOTS

    local showItemLevel = (not CludesUIDB) or (CludesUIDB.showItemLevel ~= false)

    for _, slotKey in ipairs(slotList) do
        local slotFrame = _G[slotKey]
        if slotFrame and GetFFD(slotFrame).itemLevelLabel then
            if showItemLevel then
                GetFFD(slotFrame).itemLevelLabel:Show()
            else
                GetFFD(slotFrame).itemLevelLabel:Hide()
            end
        end
    end
end
