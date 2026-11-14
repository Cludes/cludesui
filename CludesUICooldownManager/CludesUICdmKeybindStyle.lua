if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local _, mod = ...

-- Shared by live icons and the options preview. No events, hooks or polling.
-- Decorations belong to CUI's text overlay, never to a Blizzard frame.
local Pix = CludesUI.PP
-- The options page pool's table (CludesUI_PixelPerfect.lua makes it; the
-- options addon fills it in place): read through this file local, never the
-- public slot, so nothing written to that slot later reaches the live icons.
local POOL = CludesUI._Pool
local badges
local anchors = {
    TOPLEFT = true,
    TOP = true,
    TOPRIGHT = true,
    LEFT = true,
    CENTER = true,
    RIGHT = true,
    BOTTOMLEFT = true,
    BOTTOM = true,
    BOTTOMRIGHT = true,
}

-- Style pass (settings edges): builds the badge on first need, then places
-- and paints it for `bd`. It sits under the label's overlay so the label
-- always draws on top: the fill two levels down, its pixel border one down.
local function StyleBadge(textValue, edge, scale)
    local badge = badges and badges[textValue]
    local bgAlpha = edge and edge.keybindBackgroundA or 0
    local borderAlpha = edge and edge.keybindBorderA or 0
    local borderSize = edge and edge.keybindBorderSize or 1
    local enabled = edge and edge.showKeybind and (bgAlpha > 0 or (borderAlpha > 0 and borderSize > 0))
        or false
    if not badge then
        if not enabled then
            return nil
        end
        if not badges then
            badges = setmetatable({}, { __mode = "k" })
        end
        -- Pooled with the options preview's text overlay (an options page pool
        -- host); the plain CreateFrame on a live icon.
        local f = POOL.CreateFrame("Frame", nil, textValue:GetParent())
        local fillTex = f:CreateTexture(nil, "BACKGROUND")
        fillTex:SetAllPoints()
        badge = { frame = f, fill = fillTex, rim = Pix.CreateBorder(f, 1, 1, 1, 1, 1) }
        badges[textValue] = badge
    end
    badge.bd, badge.on = edge, enabled
    local f = badge.frame
    if not enabled then
        f:Hide()
        return badge
    end
    local level = textValue:GetParent():GetFrameLevel() - 2
    if level < 0 then
        level = 0
    end
    f:SetFrameLevel(level)
    badge.rim:SetFrameLevel(level + 1)
    scale = scale or badge.scale or 1
    badge.scale = scale
    local padding = (edge.keybindPadding or 2) * scale
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", textValue, "TOPLEFT", -padding, padding)
    f:SetPoint("BOTTOMRIGHT", textValue, "BOTTOMRIGHT", padding, -padding)
    badge.fill:SetColorTexture(
        edge.keybindBackgroundR or 0,
        edge.keybindBackgroundG or 0,
        edge.keybindBackgroundB or 0,
        bgAlpha
    )
    badge.fill:SetShown(bgAlpha > 0)
    if borderAlpha > 0 and borderSize > 0 then
        Pix.UpdateBorder(
            f,
            borderSize,
            edge.keybindBorderR or 1,
            edge.keybindBorderG or 1,
            edge.keybindBorderB or 1,
            borderAlpha
        )
        badge.rim:Show()
    else
        badge.rim:Hide()
    end
    return badge
end

-- Visibility pass: the badge follows its label, so a recycled or unbound
-- icon never keeps an empty badge.
local function ShowBadge(textValue, badge)
    local isShown = badge.on and textValue:IsShown()
    if isShown then
        local value = textValue:GetText()
        isShown = value ~= nil and value ~= ""
    end
    badge.frame:SetShown(isShown)
end

-- Style + visibility: settings edges and the options preview.
local function RefreshBadge(textValue, edge, scale)
    local badge = StyleBadge(textValue, edge, scale)
    if badge then
        ShowBadge(textValue, badge)
    end
end
mod.RefreshCDMKeybindBadge = RefreshBadge

-- The options preview dresses a pooled label again for a new preview: its
-- badge of the previous dress went with that dress, so it is built anew.
function mod.CdmForgetKeybindBadge(textValue)
    if badges then
        badges[textValue] = nil
    end
end

-- Visibility pass for the keybind apply paths (every CDM icon, the Rotation
-- Assist Icon). It restyles only when the label now belongs to other
-- settings than its last style pass (a recycled icon, a profile swap).
function mod.ShowCDMKeybindBadge(textValue, edge)
    local badge = badges and badges[textValue]
    if not badge then
        if not (edge and edge.showKeybind and (edge.keybindBackgroundA or edge.keybindBorderA)) then
            return
        end
        badge = StyleBadge(textValue, edge)
        if not badge then
            return
        end
    elseif badge.bd ~= edge then
        StyleBadge(textValue, edge)
    end
    ShowBadge(textValue, badge)
end

function mod.StyleCDMKeybind(textValue, edge, anchorFrame, scale, fontFile)
    if not edge.showKeybind then
        -- Existing badges can survive a bar/profile switch; no allocation.
        textValue:Hide()
        if badges and badges[textValue] then
            RefreshBadge(textValue, edge)
        end
        return
    end
    scale = scale or 1
    local font = edge.keybindFont
    if font and font ~= "__global" then
        fontFile = CludesUI.ResolveFontName(font)
    end
    local dim = (edge.keybindSize or 10) * scale
    local outline = edge.keybindOutline
    if outline == "NONE" then
        -- The suite's plain text: no outline token, drop shadow.
        CludesUI.ApplyModuleFont(textValue, fontFile, dim, "cdm", "")
    elseif outline == "OUTLINE" or outline == "THICKOUTLINE" then
        CludesUI.ApplyModuleFont(textValue, fontFile, dim, "cdm", CludesUI.SlugFlag(outline .. ", SLUG"))
    else
        CludesUI.ApplyIconTextFont(textValue, fontFile, dim, "cdm")
    end
    local anchorPoint = edge.keybindAnchor
    if not anchors[anchorPoint] then
        anchorPoint = edge.keybindAlign == "right" and "TOPRIGHT" or "TOPLEFT"
    end
    local right = anchorPoint:find("RIGHT", 1, true)
    textValue:SetJustifyH(right and "RIGHT" or (anchorPoint:find("LEFT", 1, true) and "LEFT" or "CENTER"))
    local posX = (edge.keybindOffsetX or 2) * scale
    textValue:ClearAllPoints()
    textValue:SetPoint(
        anchorPoint,
        anchorFrame,
        anchorPoint,
        right and -posX or posX,
        (edge.keybindOffsetY or -2) * scale
    )
    textValue:SetTextColor(edge.keybindR or 1, edge.keybindG or 1, edge.keybindB or 1, edge.keybindA or 0.9)
    if edge.keybindBackgroundA or edge.keybindBorderA or (badges and badges[textValue]) then
        RefreshBadge(textValue, edge, scale)
    end
end
