if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-- Explicit point relationships. Legacy side anchors keep their existing math.
local _, mod = ...
mod = mod.__cuiCoreNS or mod
local PA = {}
mod.PointAnchors = PA

local POINTS = {
    TOPLEFT = { 0, 1 },
    TOP = { 0.5, 1 },
    TOPRIGHT = { 1, 1 },
    LEFT = { 0, 0.5 },
    CENTER = { 0.5, 0.5 },
    RIGHT = { 1, 0.5 },
    BOTTOMLEFT = { 0, 0 },
    BOTTOM = { 0.5, 0 },
    BOTTOMRIGHT = { 1, 0 },
}
PA.order = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }

-- The points' English names, built once. The picker translates them through
-- literal L calls of its own, which is what the static key extractor reads.
local LABELS = {
    TOPLEFT = "Top Left",
    TOP = "Top",
    TOPRIGHT = "Top Right",
    LEFT = "Left",
    CENTER = "Center",
    RIGHT = "Right",
    BOTTOMLEFT = "Bottom Left",
    BOTTOM = "Bottom",
    BOTTOMRIGHT = "Bottom Right",
}
PA.LABELS = LABELS

function PA.Description(details)
    return CUI.Lf(
        "Point: %1$s to %2$s",
        CUI.L(LABELS[details.sourcePoint] or "?"),
        CUI.L(LABELS[details.targetPoint] or "?")
    )
end

local function Number(val)
    return not (issecretvalue and issecretvalue(val))
        and type(val) == "number"
        and val == val
        and val > -math.huge
        and val < math.huge
end

function PA.Is(details) return type(details) == "table" and details.mode == "POINT" end

function PA.Valid(details)
    return PA.Is(details)
        and type(details.target) == "string"
        and POINTS[details.sourcePoint] ~= nil
        and POINTS[details.targetPoint] ~= nil
        and Number(details.offsetX)
        and Number(details.offsetY)
end

function CUI.GetUnlockAnchorSide(details)
    if not PA.Is(details) then return details and details.side end
    if not PA.Valid(details) then return end
    local s, t = POINTS[details.sourcePoint], POINTS[details.targetPoint]
    if not s or not t then return end
    if s[1] == t[1] then
        if s[2] == 0 and t[2] == 1 then return "TOP" end
        if s[2] == 1 and t[2] == 0 then return "BOTTOM" end
    end
    if s[2] == t[2] then
        if s[1] == 0 and t[1] == 1 then return "RIGHT" end
        if s[1] == 1 and t[1] == 0 then return "LEFT" end
    end
end

function CUI.IsPointAnchored(key)
    local saved = CludesUIDB and CludesUIDB.unlockAnchors
    return saved and PA.Is(saved[key]) or false
end

function CUI.SetPointAnchorHandles(enabled)
    CludesUIDB.unlockPointHandles = enabled and true or nil
    if not enabled and PA.cancelPicker then PA.cancelPicker() end
end

function PA.Frame(key)
    local elem = CUI._unlockRegisteredElements[key]
    return elem and elem.getFrame and elem.getFrame(key)
end

local function Insets(key, widget)
    local elem = CUI._unlockRegisteredElements[key]
    local l, r, t, b = 0, 0, 0, 0
    if elem and elem.getInsets then
        l, r, t, b = elem.getInsets(key)
        l, r, t, b = l or 0, r or 0, t or 0, b or 0
    end
    local extra = elem and elem.getBottomExtra and elem.getBottomExtra(key) or 0
    if not (Number(l) and Number(r) and Number(t) and Number(b) and Number(extra)) then return end
    return l, r, t, b - extra
end

local function Bounds(widget)
    return widget:GetLeft(),
        widget:GetRight(),
        widget:GetTop(),
        widget:GetBottom(),
        widget:GetEffectiveScale()
end

local function Dimensions(widget) return widget:GetWidth(), widget:GetHeight(), widget:GetEffectiveScale() end

local function EdgeExtent(key, side, fallback)
    local success, value = pcall(CUI._GetAnchorTargetExtent, key, side)
    if not success then return end
    if issecretvalue and issecretvalue(value) then return end
    if value == nil then return fallback end
    if Number(value) then return value end
end

function PA.Rect(key, widget, target)
    if not widget then return end
    local success, l, r, t, b, scale = pcall(Bounds, widget)
    if
        not success
        or not (Number(l) and Number(r) and Number(t) and Number(b) and Number(scale) and scale > 0)
    then
        return
    end
    local safe, il, ir, it, ib = pcall(Insets, key, widget)
    if not safe or not il then return end
    local ratio = scale / UIParent:GetEffectiveScale()
    l, r, t, b = (l + il) * ratio, (r - ir) * ratio, (t - it) * ratio, (b + ib) * ratio
    if target and CUI._GetAnchorTargetExtent then
        l, r = EdgeExtent(key, "LEFT", l), EdgeExtent(key, "RIGHT", r)
        t, b = EdgeExtent(key, "TOP", t), EdgeExtent(key, "BOTTOM", b)
    end
    if not (Number(l) and Number(r) and Number(t) and Number(b)) or r <= l or t <= b then return end
    return l, r, t, b
end

function PA.Point(key, widget, anchorPoint, target)
    local p = POINTS[anchorPoint]
    if not p then return end
    local l, r, t, b = PA.Rect(key, widget, target)
    if not l then return end
    return l + (r - l) * p[1], b + (t - b) * p[2]
end

function PA.Center(childKey, childFrame, details, target, wid, hgt)
    if not PA.Valid(details) then return end
    -- Contradictory imported chains must not keep scheduling position changes.
    local key = details.target
    local saved = CludesUIDB and CludesUIDB.unlockAnchors
    for idx = 1, 100 do
        if key == childKey then return end
        local hostFrame = saved and saved[key]
        if not hostFrame or not hostFrame.target then break end
        key = hostFrame.target
        if idx == 100 then return end
    end
    local tx, ty = PA.Point(details.target, target, details.targetPoint, true)
    if not tx then return end
    local success, fw, fh, scale = pcall(Dimensions, childFrame)
    if not success or not (Number(scale) and scale > 0) then return end
    local ratio = scale / UIParent:GetEffectiveScale()
    if not wid or not hgt then
        if not (Number(fw) and Number(fh)) then return end
        wid, hgt = fw * ratio, fh * ratio
    end
    if not (Number(wid) and Number(hgt)) or wid <= 0 or hgt <= 0 then return end
    local l, r, t, b = Insets(childKey, childFrame)
    if not l then return end
    l, r, t, b = -wid / 2 + l * ratio, wid / 2 - r * ratio, hgt / 2 - t * ratio, -hgt / 2 + b * ratio
    local p = POINTS[details.sourcePoint]
    return tx + details.offsetX - (l + (r - l) * p[1]), ty + details.offsetY - (b + (t - b) * p[2])
end

local function WritePoint(widget, anchorPoint, rel, rp, posX, posY)
    CUI.ClearFramePoints(widget)
    CUI.SetFramePoint(widget, anchorPoint, rel, rp, posX, posY)
end

function PA.Capture(childKey, details, childFrame, target)
    if not PA.Valid(details) then return end
    childFrame, target = childFrame or PA.Frame(childKey), target or PA.Frame(details.target)
    local cx, cy = PA.Point(childKey, childFrame, details.sourcePoint)
    local tx, ty = PA.Point(details.target, target, details.targetPoint, true)
    if not cx or not tx then return end
    local ex, ey = 0, 0
    if CUI._ExtraAnchorOffset then
        ex, ey = CUI._ExtraAnchorOffset(childKey)
    end
    local ratio = childFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return cx - tx - ex * ratio, cy - ty - ey * ratio
end

-- Keep the selected native point fixed between resize notifications as well.
function PA.Place(childKey, childFrame, details, cx, cy, wid, hgt)
    local pp = CUI.PP
    local scale = childFrame:GetEffectiveScale()
    local ratio = UIParent:GetEffectiveScale() / scale
    local bx, by = pp.SnapCenterForDim(cx * ratio, wid, scale), pp.SnapCenterForDim(cy * ratio, hgt, scale)
    local ex, ey = 0, 0
    if CUI._ExtraAnchorOffset then
        ex, ey = CUI._ExtraAnchorOffset(childKey)
    end
    bx, by = bx + ex, by + ey
    local p = POINTS[details.sourcePoint]
    local posX, posY = bx + (p[1] - 0.5) * wid, by + (p[2] - 0.5) * hgt
    local rel, rp = UIParent, "CENTER"
    if p and POINTS[details.targetPoint][2] == 0 and CUI._GetAnchorFollowFrame then
        local follow = CUI._GetAnchorFollowFrame(childKey, details.target, "BOTTOM")
        local tx, ty = PA.Point(details.target, PA.Frame(details.target), details.targetPoint, true)
        if follow and tx then
            rel, rp = follow, details.targetPoint
            posX = posX - (tx - UIParent:GetWidth() / 2) * ratio
            posY = posY - (ty - UIParent:GetHeight() / 2) * ratio
        end
    end
    local success, pt, rt, rpt, px, py = pcall(childFrame.GetPoint, childFrame, 1)
    local plain = success
        and not (
            issecretvalue
            and (
                issecretvalue(pt)
                or issecretvalue(rt)
                or issecretvalue(rpt)
                or issecretvalue(px)
                or issecretvalue(py)
            )
        )
    local tolerance = pp.perfect / scale * 0.25
    local same = plain
        and childFrame:GetNumPoints() == 1
        and pt == details.sourcePoint
        and rt == rel
        and rpt == rp
        and Number(px)
        and Number(py)
        and math.abs(px - posX) <= tolerance
        and math.abs(py - posY) <= tolerance
    if not plain and PA.followPins then
        local last = PA.followPins[childFrame]
        same = last
            and last.info == details
            and last.rel == rel
            and last.point == details.sourcePoint
            and last.rp == rp
            and math.abs(last.x - posX) <= tolerance
            and math.abs(last.y - posY) <= tolerance
    end
    if not same then
        local placed = pcall(WritePoint, childFrame, details.sourcePoint, rel, rp, posX, posY)
        if not placed then return end
        if rel ~= UIParent then
            PA.followPins = PA.followPins or setmetatable({}, { __mode = "k" })
            PA.followPins[childFrame] =
                { info = details, rel = rel, point = details.sourcePoint, rp = rp, x = posX, y = posY }
        elseif PA.followPins then
            PA.followPins[childFrame] = nil
        end
    end
    return bx, by, not same
end

function PA.EarlyApply(key, details, childFrame, target)
    if not PA.Valid(details) or (InCombatLockdown() and childFrame:IsProtected()) then return end
    local cx, cy = PA.Center(key, childFrame, details, target)
    if not cx then return end
    PA.Place(
        key,
        childFrame,
        details,
        cx - UIParent:GetWidth() / 2,
        cy - UIParent:GetHeight() / 2,
        childFrame:GetWidth(),
        childFrame:GetHeight()
    )
end

function PA.Recenter(key, LM)
    local details = LM.GetAnchorInfo(key)
    if not PA.Is(details) then return false end
    local mover = LM.movers[key]
    if not (mover and mover._dragging) then LM.ApplyAnchorPosition(key, details.target, nil, true) end
    return true
end

-- Old builds reject version 4 rather than silently reading point links as sides.
function CUI.LayoutExportVersion(value, seen)
    if type(value) ~= "table" then return 3 end
    if PA.Is(value) then return 4 end
    seen = seen or {}
    if seen[value] then return 3 end
    seen[value] = true
    for _, val in pairs(value) do
        if type(val) == "table" and CUI.LayoutExportVersion(val, seen) == 4 then return 4 end
    end
    return 3
end
