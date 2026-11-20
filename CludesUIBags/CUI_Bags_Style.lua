if CUI_CLIENT_BLOCKED then
    return
end
local mod = select(2, ...)
local CUI = CludesUI
local forever
local BAG_FRAME_SCALE = 0.8

--- The WoW Forever style a Bags profile p asks for: its own pick
--- (useForeverStyle true or false), else the look most of the profile's modules
--- use (CludesUI.ForeverLookMajority over addons, nil = the active
--- profile's), so a profile on the WoW Forever look gets it with no write.
function mod.BagsForeverWanted(profile, addons)
    local pick = profile and profile.useForeverStyle
    if pick == nil then
        return CUI.ForeverLookMajority(addons)
    end
    return pick == true
end

-- Latched at the first read (0.5 s after login: every module has loaded), so a
-- change takes effect after the reload the Style page asks for.
function mod.BagsForever()
    if not CUI.IS_FOREVER then
        return false
    end
    if forever == nil then
        if not CUI.Lite.IsDBReady() then
            return false
        end
        forever = mod.BagsForeverWanted(CUI._bagsDB.profile)
    end
    return forever
end

local function InsetBagBackground(texture, ownerFrame)
    local inset = CUI.FOREVER_HEAVY.fill * BAG_FRAME_SCALE
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", ownerFrame, "TOPLEFT", inset, -inset)
    texture:SetPoint("BOTTOMRIGHT", ownerFrame, "BOTTOMRIGHT", -inset, inset)
end

function mod.SkinForeverBagWindow(ownerFrame, backdrop, overlayFrame, hasTitle, hasPortrait)
    if not mod.BagsForever() then
        return
    end
    local nineSlice = hasPortrait and NineSliceUtil
    local layout = nineSlice
        and nineSlice.GetLayout
        and nineSlice.ApplyLayout
        and nineSlice.GetLayout("HeldBagLayout")
    local corner = layout and layout.TopLeftCorner
    local cornerInfo = corner and corner.atlas and C_Texture.GetAtlasInfo(corner.atlas)
    local heavyOK = CUI.ForeverHeavyOK()
    if cornerInfo and heavyOK then
        local border = CreateFrame("Frame", nil, ownerFrame)
        border:SetUsingParentLevel(true)
        border:SetScale(BAG_FRAME_SCALE)
        border.layoutType = "HeldBagLayout"
        nineSlice.ApplyLayout(border, layout)
        -- Let the straight rail cover the notch at the portrait corner's far end.
        local piece = border.TopLeftCorner
        local file = cornerInfo.file or cornerInfo.filename
        local width = 64
        if piece and file and cornerInfo.width > width then
            local leftX, right = cornerInfo.leftTexCoord, cornerInfo.rightTexCoord
            piece:SetTexture(file)
            piece:SetTexCoord(
                leftX,
                leftX + (right - leftX) * width / cornerInfo.width,
                cornerInfo.topTexCoord,
                cornerInfo.bottomTexCoord
            )
            piece:SetSize(width, cornerInfo.height)
        end
        if nineSlice.UpdateCornerCropping then
            local panelFrame = { NineSlice = border }
            border:SetScript("OnSizeChanged", function(_, _, height)
                nineSlice.UpdateCornerCropping(panelFrame, height)
            end)
        end
        -- Align the visible rim with the window; the native slices include a shadow.
        border:SetPoint("TOPLEFT", ownerFrame, "TOPLEFT", 1, -3)
        border:SetPoint("BOTTOMRIGHT", ownerFrame, "BOTTOMRIGHT", -1, -4.5)
        ownerFrame._foreverBagPortraitFrame = border
    elseif heavyOK then
        local border = CreateFrame("Frame", nil, ownerFrame)
        border:SetUsingParentLevel(true)
        border:SetScale(BAG_FRAME_SCALE)
        border:SetAllPoints(ownerFrame)
        local heavy = CUI.ForeverHeavy(border, "ARTWORK", 1)
        CUI.ForeverHeavySeat(heavy, ownerFrame)
        CUI.ForeverHeavyTitle(heavy, hasTitle)
    else
        CUI.ForeverBorderSeat(CUI.ForeverBorder(ownerFrame, "ARTWORK", 1, nil, "slim"), ownerFrame)
    end
    if heavyOK then
        ownerFrame._foreverBagFrameScale = BAG_FRAME_SCALE
        InsetBagBackground(backdrop, ownerFrame)
        if overlayFrame then
            InsetBagBackground(overlayFrame, ownerFrame)
        end
    end
    backdrop:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock")
    backdrop:SetVertexColor(0.55, 0.55, 0.55)
    return true
end

function mod.LayoutForeverBagHeader(header, height)
    local scale = header:GetParent()._foreverBagFrameScale or 1
    local trim = CUI.FOREVER_HEAVY.title.bottom * (1 - scale)
    -- The header starts one unit inside the window rim.
    header._foreverTitleY = 1 - 14 * scale
    header._foreverControlsY = 1 - 15 * scale
    header._foreverToolsY = -39 + trim
    header:SetHeight((height or 54) - trim)
end

function mod.SkinForeverBagTitle(title, total)
    local header = title:GetParent()
    local posY = header._foreverTitleY
    title:ClearAllPoints()
    title:SetPoint("LEFT", header, "TOPLEFT", total and 55 or 40, posY)
    title:SetPoint("RIGHT", header, "TOPRIGHT", total and -124 or -30, posY)
    title:SetJustifyH("CENTER")
    title:SetWordWrap(false)
    title:SetTextColor(1, 0.82, 0)
    if not total then
        return
    end
    total:ClearAllPoints()
    total:SetPoint("RIGHT", header, "TOPRIGHT", -31, posY)
    total:SetWidth(85)
    total:SetJustifyH("RIGHT")
    total:SetWordWrap(false)
    total:SetTextColor(0.87, 0.77, 0.59)
end

function mod.ForeverBagSidebarInset(ownerFrame)
    return CUI.FOREVER_HEAVY.band * (ownerFrame._foreverBagFrameScale or 1)
end

function mod.AnchorBagSidebarIcon(iconTex, collapsed, leftX)
    iconTex:ClearAllPoints()
    if collapsed then
        iconTex:SetPoint("CENTER")
    else
        iconTex:SetPoint("LEFT", leftX, 0)
    end
end

function mod.SetForeverBagSectionColors(labelText, line, depth)
    local shade, alpha = 1, 0.5
    if depth == 1 then
        shade, alpha = 0.8, 0.25
    elseif depth and depth >= 2 then
        shade, alpha = 0.65, 0.15
    end
    labelText:SetTextColor(0.88 * shade, 0.77 * shade, 0.58 * shade)
    line:SetColorTexture(0.56, 0.41, 0.26, alpha)
end

function mod.AddForeverBagPortrait(header, texturePath)
    local border = header:GetParent()._foreverBagPortraitFrame
    local art = border or header
    local iconTex = art:CreateTexture(nil, "ARTWORK")
    local size = border and 36 or 28
    iconTex:SetSize(size, size)
    iconTex:SetTexture(texturePath)

    local mask = art:CreateMaskTexture()
    if border then
        iconTex:SetPoint("TOPLEFT", border, "TOPLEFT", -4, 1)
        mask:SetPoint("TOPLEFT", iconTex, "TOPLEFT", 2, 0)
        mask:SetPoint("BOTTOMRIGHT", iconTex, "BOTTOMRIGHT", -2, 4)
    else
        iconTex:SetPoint("CENTER", header, "TOPLEFT", 16, -18)
        mask:SetAllPoints(iconTex)
    end
    mask:SetTexture(
        "Interface\\CharacterFrame\\TempPortraitAlphaMask",
        "CLAMPTOBLACKADDITIVE",
        "CLAMPTOBLACKADDITIVE"
    )
    iconTex:AddMaskTexture(mask)

    if not border and C_Texture.GetAtlasInfo("UI-Frame-Portrait") then
        local rim = header:CreateTexture(nil, "ARTWORK", nil, 1)
        rim:SetAtlas("UI-Frame-Portrait")
        rim:SetSize(40, 40)
        rim:SetPoint("CENTER", iconTex)
    end
end

function mod.PositionForeverBagClose(close)
    local header = close:GetParent()
    local scale = header:GetParent()._foreverBagFrameScale or 1
    close:ClearAllPoints()
    close:SetPoint("CENTER", header, "TOPRIGHT", -12, 1 - 13 * scale)
    local size = 25 * scale
    close:SetSize(size, size)
    if not C_Texture.GetAtlasInfo("RedButton-Exit") then
        return
    end
    close.icon:Hide()
    close:SetScript("OnEnter", nil)
    close:SetScript("OnLeave", nil)
    close:SetNormalAtlas("RedButton-Exit")
    if C_Texture.GetAtlasInfo("RedButton-exit-pressed") then
        close:SetPushedAtlas("RedButton-exit-pressed")
    end
    if C_Texture.GetAtlasInfo("RedButton-Highlight") then
        close:SetHighlightAtlas("RedButton-Highlight", "ADD")
    end
end

function mod.SkinForeverBagSearch(search, backdrop, placeholder, clear)
    local getAtlas = C_Texture.GetAtlasInfo
    search:SetHeight(20)
    if
        getAtlas("common-search-border-left")
        and getAtlas("common-search-border-middle")
        and getAtlas("common-search-border-right")
    then
        local leftX = search:CreateTexture(nil, "BACKGROUND")
        leftX:SetAtlas("common-search-border-left")
        leftX:SetSize(8, 20)
        leftX:SetPoint("LEFT", -5, 0)
        local right = search:CreateTexture(nil, "BACKGROUND")
        right:SetAtlas("common-search-border-right")
        right:SetSize(8, 20)
        right:SetPoint("RIGHT")
        backdrop:ClearAllPoints()
        backdrop:SetAtlas("common-search-border-middle")
        backdrop:SetPoint("TOPLEFT", leftX, "TOPRIGHT")
        backdrop:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
    else
        backdrop:SetColorTexture(0.035, 0.03, 0.025, 0.92)
        local border = CUI.ForeverBorder(search, "ARTWORK", 1, nil, "slim")
        CUI.ForeverBorderSeat(border, search)
        CUI.ForeverBorderPaint(border, 0.65, 0.60, 0.52, 1, true)
    end

    local iconTex = search:CreateTexture(nil, "ARTWORK", nil, 2)
    if getAtlas("common-search-magnifyingglass") then
        iconTex:SetAtlas("common-search-magnifyingglass")
    else
        iconTex:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    end
    iconTex:SetSize(10, 10)
    iconTex:SetPoint("LEFT", 1, -1)
    iconTex:SetVertexColor(0.6, 0.6, 0.6)
    search:SetTextInsets(16, 20, 0, 0)
    placeholder:ClearAllPoints()
    placeholder:SetPoint("LEFT", search, "LEFT", 16, 0)
    placeholder:SetTextColor(0.35, 0.35, 0.35)
    if SEARCH then
        placeholder:SetText(SEARCH)
    end

    if getAtlas("common-search-clearbutton") then
        clear.tex:Hide()
        local glyph = clear:CreateTexture(nil, "ARTWORK")
        glyph:SetAtlas("common-search-clearbutton")
        glyph:SetSize(10, 10)
        glyph:SetPoint("CENTER")
        glyph:SetAlpha(0.7)
    end
end

function mod.SkinForeverBagFooter(footer, backdrop, separator)
    if separator then
        separator:Hide()
    end
    -- Keep the coin box on the bottom row when tracked currencies wrap.
    local rowCenter = footer:GetHeight() / 2
    backdrop:ClearAllPoints()
    backdrop:SetHeight(22)
    backdrop:SetPoint("LEFT", footer, "BOTTOMLEFT", 7, rowCenter)
    backdrop:SetPoint("RIGHT", footer, "BOTTOMRIGHT", -7, rowCenter)
    backdrop:SetColorTexture(0.025, 0.02, 0.015, 0.8)
    footer._coinBox = backdrop

    if
        not (
            C_Texture.GetAtlasInfo("common-coinbox-left")
            and C_Texture.GetAtlasInfo("common-coinbox-right")
            and C_Texture.GetAtlasInfo("_common-coinbox-center")
        )
    then
        return
    end

    local leftX = footer:CreateTexture(nil, "BACKGROUND", nil, 2)
    leftX:SetAtlas("common-coinbox-left")
    leftX:SetWidth(8)
    leftX:SetPoint("TOPLEFT", backdrop)
    leftX:SetPoint("BOTTOMLEFT", backdrop)
    local right = footer:CreateTexture(nil, "BACKGROUND", nil, 2)
    right:SetAtlas("common-coinbox-right")
    right:SetWidth(8)
    right:SetPoint("TOPRIGHT", backdrop)
    right:SetPoint("BOTTOMRIGHT", backdrop)
    local middle = footer:CreateTexture(nil, "BACKGROUND", nil, 2)
    middle:SetAtlas("_common-coinbox-center")
    middle:SetHorizTile(true)
    middle:SetPoint("TOPLEFT", leftX, "TOPRIGHT")
    middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
end
