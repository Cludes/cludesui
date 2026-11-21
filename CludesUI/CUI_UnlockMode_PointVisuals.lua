if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
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

function CUI.GetPointAnchorColor(kind)
    local colors = CludesUIDB and CludesUIDB.unlockPointColors
    local color = colors and colors[kind] or defaultSet[kind]
    return unpack(color)
end

function visuals.ColorDot(art, alpha)
    art.colorAlpha = alpha
    local red, green, blue, a = CUI.GetPointAnchorColor("point")
    art.fill:SetVertexColor(red, green, blue, a * alpha)
    red, green, blue, a = CUI.GetPointAnchorColor("border")
    art.border:SetVertexColor(red, green, blue, a * alpha)
end

function CUI.SetPointAnchorColor(kind, red, green, blue, a)
    if not defaultSet[kind] then return end
    CludesUIDB.unlockPointColors = CludesUIDB.unlockPointColors or {}
    CludesUIDB.unlockPointColors[kind] = { red, green, blue, a }
    if dots and kind ~= "line" then
        for idx = 1, #dots do
            visuals.ColorDot(dots[idx], dots[idx].colorAlpha)
        end
    end
end

function visuals.SizeDot(art, size)
    local pp = CUI.PP
    local px = pp.perfect / art:GetEffectiveScale()
    if art.dotSize == size and art.pixelSize == px then return end
    art.dotSize, art.pixelSize = size, px
    art:SetSize(size, size)
    -- Matched cells prefilter both edges at their displayed pixel size.
    local diameter = math.max(1, math.min(16, math.floor(size / px + 0.5)))
    local cell = diameter - 1
    local posX, posY = (cell % 4) * 64, math.floor(cell / 4) * 64
    local padded = size * (diameter + 2) / diameter
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
    local fill = art:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("CENTER", art, "CENTER")
    fill:SetTexture(DOT_FILL, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "LINEAR")
    fill:SetSnapToPixelGrid(false)
    fill:SetTexelSnappingBias(0)
    art.fill, art.border = fill, border
    visuals.ColorDot(art, 1)
    dots = dots or {}
    dots[#dots + 1] = art
    return art
end

function visuals.RaiseAboveMover(widget, mover)
    local level = mover:GetFrameLevel()
    if mover._raisedLevel then level = math.max(level, mover._raisedLevel + 100) end
    if mover._cogBtn then level = math.max(level, mover._cogBtn:GetFrameLevel()) end
    level = level + 30
    if widget:GetFrameLevel() == level then return end
    -- Fixed frames ignore SetFrameLevel until their level is unlocked.
    widget:SetFixedFrameLevel(false)
    widget:SetFrameLevel(level)
    widget:SetFixedFrameLevel(true)
end

local markers
local function ShowPoint(index, mover, anchorPoint, alpha)
    local marker = markers[index]
    if not marker then
        marker = visuals.CreateDot(mover)
        markers[index] = marker
    end
    if marker:GetParent() ~= mover then marker:SetParent(mover) end
    visuals.RaiseAboveMover(marker, mover)
    if marker.point ~= anchorPoint or marker.mover ~= mover then
        marker:ClearAllPoints()
        marker:SetPoint("CENTER", mover, anchorPoint)
        marker.point, marker.mover = anchorPoint, mover
    end
    local pp = CUI.PP
    local size = visuals.idleSize * pp.perfect / marker:GetEffectiveScale()
    visuals.SizeDot(marker, size)
    marker:SetAlpha(alpha)
    marker:Show()
end

function visuals.Connection(index, source, sourcePoint, target, targetPoint, alpha)
    markers = markers or {}
    ShowPoint(index * 2 - 1, source, sourcePoint, alpha)
    ShowPoint(index * 2, target, targetPoint, alpha)
end

function visuals.TrimConnections(total)
    if not markers then return end
    for idx = total * 2 + 1, #markers do
        markers[idx]:Hide()
    end
end
