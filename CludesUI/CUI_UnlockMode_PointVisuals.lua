if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-- Shared dot art and passive connection endpoints. Nothing is built until used.
local _, mod = ...
mod = mod.__cuiCoreNS or mod
local visuals = {}
mod.PointVisuals = visuals
local DOT_FILL = "Interface\\AddOns\\CludesUI\\media\\basics\\point_anchor_fill.tga"
local DOT_BORDER = "Interface\\AddOns\\CludesUI\\media\\basics\\point_anchor_border.tga"
visuals.idleSize, visuals.hoverSize = 8, 12
local defaultSet = { point = { 1, 1, 1, 1 }, border = { 0, 0, 0, 1 }, line = { 1, 0.2, 0.2, 1 } }
local dots

function CludesUI.GetPointAnchorColor(kindOf)
    local colors = CludesUIDB and CludesUIDB.unlockPointColors
    local color = colors and colors[kindOf] or defaultSet[kindOf]
    return unpack(color)
end

function visuals.ColorDot(art, alpha)
    art.colorAlpha = alpha
    local r, g, b, a = CludesUI.GetPointAnchorColor("point")
    art.fill:SetVertexColor(r, g, b, a * alpha)
    r, g, b, a = CludesUI.GetPointAnchorColor("border")
    art.border:SetVertexColor(r, g, b, a * alpha)
end

function CludesUI.SetPointAnchorColor(kindOf, r, g, b, a)
    if not defaultSet[kindOf] then
        return
    end
    CludesUIDB.unlockPointColors = CludesUIDB.unlockPointColors or {}
    CludesUIDB.unlockPointColors[kindOf] = { r, g, b, a }
    if dots and kindOf ~= "line" then
        for idx = 1, #dots do
            visuals.ColorDot(dots[idx], dots[idx].colorAlpha)
        end
    end
end

function visuals.SizeDot(art, dim)
    local pp = CludesUI.PP
    local px = pp.perfect / art:GetEffectiveScale()
    if art.dotSize == dim and art.pixelSize == px then
        return
    end
    art.dotSize, art.pixelSize = dim, px
    art:SetSize(dim, dim)
    -- Matched cells prefilter both edges at their displayed pixel size.
    local diameter = math.max(1, math.min(16, math.floor(dim / px + 0.5)))
    local cellFrame = diameter - 1
    local posX, posY = (cellFrame % 4) * 64, math.floor(cellFrame / 4) * 64
    local padded = dim * (diameter + 2) / diameter
    art.fill:SetSize(padded, padded)
    art.border:SetSize(padded, padded)
    art.fill:SetTexCoord(posX / 256, (posX + 64) / 256, posY / 256, (posY + 64) / 256)
    art.border:SetTexCoord(posX / 256, (posX + 64) / 256, posY / 256, (posY + 64) / 256)
end

function visuals.CreateDot(hostFrame)
    local art = CreateFrame("Frame", nil, hostFrame)
    art:EnableMouse(false)
    local border = art:CreateTexture(nil, "OVERLAY")
    border:SetPoint("CENTER", art, "CENTER")
    border:SetTexture(DOT_BORDER, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "LINEAR")
    border:SetSnapToPixelGrid(false)
    border:SetTexelSnappingBias(0)
    local fillTex = art:CreateTexture(nil, "ARTWORK")
    fillTex:SetPoint("CENTER", art, "CENTER")
    fillTex:SetTexture(DOT_FILL, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "LINEAR")
    fillTex:SetSnapToPixelGrid(false)
    fillTex:SetTexelSnappingBias(0)
    art.fill, art.border = fillTex, border
    visuals.ColorDot(art, 1)
    dots = dots or {}
    dots[#dots + 1] = art
    return art
end

function visuals.RaiseAboveMover(widget, mover)
    local level = mover:GetFrameLevel()
    if mover._raisedLevel then
        level = math.max(level, mover._raisedLevel + 100)
    end
    if mover._cogBtn then
        level = math.max(level, mover._cogBtn:GetFrameLevel())
    end
    level = level + 30
    if widget:GetFrameLevel() == level then
        return
    end
    -- Fixed frames ignore SetFrameLevel until their level is unlocked.
    widget:SetFixedFrameLevel(false)
    widget:SetFrameLevel(level)
    widget:SetFixedFrameLevel(true)
end

local markers
local function ShowPoint(slotPos, mover, anchorPoint, alpha)
    local marker = markers[slotPos]
    if not marker then
        marker = visuals.CreateDot(mover)
        markers[slotPos] = marker
    end
    if marker:GetParent() ~= mover then
        marker:SetParent(mover)
    end
    visuals.RaiseAboveMover(marker, mover)
    if marker.point ~= anchorPoint or marker.mover ~= mover then
        marker:ClearAllPoints()
        marker:SetPoint("CENTER", mover, anchorPoint)
        marker.point, marker.mover = anchorPoint, mover
    end
    local pp = CludesUI.PP
    local dim = visuals.idleSize * pp.perfect / marker:GetEffectiveScale()
    visuals.SizeDot(marker, dim)
    marker:SetAlpha(alpha)
    marker:Show()
end

function visuals.Connection(slotPos, source, sourcePoint, targetUnit, targetPoint, alpha)
    markers = markers or {}
    ShowPoint(slotPos * 2 - 1, source, sourcePoint, alpha)
    ShowPoint(slotPos * 2, targetUnit, targetPoint, alpha)
end

function visuals.TrimConnections(total)
    if not markers then
        return
    end
    for idx = total * 2 + 1, #markers do
        markers[idx]:Hide()
    end
end
