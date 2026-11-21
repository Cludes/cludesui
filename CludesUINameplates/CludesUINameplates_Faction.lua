if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUINameplates_Faction.lua
--  Faction badge (Horde/Alliance) on friendly nameplates. Enemy plates carry it
--  as a Core Positions slot element (NameplateFrame:UpdateFaction); friendly
--  plates have no slots, so the badge sits just left of the FriendlyFrame's
--  name (full plates only: name-only plates stay just the name). This matters
--  most for unflagged opposite-faction players, who cannot be attacked and so
--  get friendly plates. Which badge (if any) and whether it is dimmed come from
--  ns.NP_FactionBadge, shared with enemy plates; the badge shows while the
--  faction slot is set (not "None").
-------------------------------------------------------------------------------
local _, mod = ...

local badges = {} -- nameplate -> badge frame (reused with the nameplate)

local function GetBadge(nameplate)
    local widget = badges[nameplate]
    if not widget then
        widget = CreateFrame("Frame", nil, nameplate)
        widget:SetFrameStrata("MEDIUM")
        widget.tex = widget:CreateTexture(nil, "ARTWORK")
        widget.tex:SetAllPoints()
        widget:Hide()
        badges[nameplate] = widget
    end
    return widget
end

-- The target's left arrow sits just left of the name; while the badge is up it
-- moves out past the badge instead of under it. Same fully-anchored form as
-- the friendly plate builds (point+size regions drift inside plate subtrees).
local function ArrowTo(fp, anchor)
    local la = fp.leftArrow
    if not la or fp._facArrowTo == anchor then return end
    fp._facArrowTo = anchor
    -- The width we set, never la:GetWidth(): the arrow hangs off the name, and a
    -- secret name (restricted content) makes its measured width secret.
    local posX = -(2 + (fp._arrowW or 16) / 2)
    la:ClearAllPoints()
    la:SetPoint("TOP", anchor, "LEFT", posX, 8)
    la:SetPoint("BOTTOM", anchor, "LEFT", posX, -8)
end

-- Draw (or hide) the badge beside a friendly full plate's name. No events of
-- its own: the friendly plate's SetUnit, the main file's shared UNIT_FACTION
-- dispatch and settings passes call it. A friendly plate exists only in
-- full-plate mode and is released before its unit becomes an enemy plate.
local function Refresh(fp)
    local nameplate, unitToken = fp.nameplate, fp.unit
    if not (nameplate and unitToken) then return end
    local widget = badges[nameplate]
    local atlas, size
    -- Slot None: no unit queries, only a badge left up from before is hidden.
    if mod.NP_GetFactionSlot() ~= "none" then
        atlas, size = mod.NP_FactionBadge(unitToken)
    end
    local fontStr = fp.name
    if not (atlas and fontStr) then
        if widget then widget:Hide() end
        if fontStr then ArrowTo(fp, fontStr) end
        return
    end
    widget = widget or GetBadge(nameplate)
    local sz = mod.NP_GetFactionIconSize()
    widget:SetSize(sz, sz)
    widget:SetFrameLevel(nameplate:GetFrameLevel() + 5)
    widget:ClearAllPoints()
    widget:SetPoint("RIGHT", fontStr, "LEFT", -2, 0)
    -- Repaint only when the art or the dim changes (inputs: faction, Icon Style, honor
    -- badge, dim).
    local style = mod.NP_GetFactionStyle()
    local badge = CludesUI.FactionBadgeFor(style, unitToken)
    if widget.facArt ~= atlas or widget.facStyle ~= style or widget.facBadge ~= badge then
        CludesUI.SetFactionArt(widget.tex, style, atlas, badge)
        widget.facArt, widget.facStyle, widget.facBadge = atlas, style, badge
    end
    if widget.facDim ~= size then
        widget.tex:SetDesaturated(size)
        widget.tex:SetAlpha(size and 0.6 or 1)
        widget.facDim = size
    end
    widget:Show()
    ArrowTo(fp, widget)
end

mod.NP_FriendlyFactionRefresh = Refresh

-- The friendly plate is released (plate removed, switch to name-only) or its
-- unit promoted to an enemy plate, which draws its own badge.
function mod.NP_FriendlyFactionHide(fp)
    local widget = fp.nameplate and badges[fp.nameplate]
    if widget then widget:Hide() end
    if fp.name then ArrowTo(fp, fp.name) end
end

-- Every friendly full plate: runs after a settings change or profile switch.
function mod.NP_RefreshFriendlyFaction()
    -- Slot None costs one compare per plate: Refresh hides and puts arrows back.
    for _, fp in pairs(mod.friendlyPlates) do
        Refresh(fp)
    end
end
