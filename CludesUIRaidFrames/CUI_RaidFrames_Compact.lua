if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_RaidFrames_Compact.lua
--  Compact Mode (the raid and party Frame Spacing cogs) and Grid Mode (the
--  raid Group Spacing cog). With a visible Pixels or Pixels Textured border,
--  frames sit one physical pixel apart and each group draws one shared
--  outline with separators between its frames instead of a border per frame;
--  Grid Mode sets the raid groups one pixel apart too and fills each occupied
--  group to five with empty backgrounds, under one outline while the groups
--  make a rectangle. Grouped pets follow their tab's mode. Nothing is built,
--  hooked or registered until a mode is first on; a mode turned off hides its
--  pieces, and the hooks it left on the unit buttons return at once.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local CUI = mod.CludesUI
local CreateFrame, InCombatLockdown = CreateFrame, InCombatLockdown
local PixelSnap, FFD, GetFFD, defaultSet = Inner.PixelSnap, Inner.FFD, Inner.GetFFD, Inner.defaults
local allButtons, separatedHdrs = Inner.allButtons, Inner.separatedHdrs
local saved, boxHolder, solidStyle
Inner.dbSetters[#Inner.dbSetters + 1] = function(val)
    saved = val
end
Inner.containerFrameSetters[#Inner.containerFrameSetters + 1] = function(val)
    boxHolder = val
end

-------------------------------------------------------------------------------
--  Gates and spacing
-------------------------------------------------------------------------------
-- The border either mode needs: a Pixels style above size 0, on the CludesUI look.
function mod.RF_CompactEligible(cfg)
    return cfg and CUI._pixelArtBorders[cfg.borderTexture] and not mod.RF_Stock() and (cfg.borderSize or 1) > 0
end

-- Compact Mode in effect for settings s (party: the Party tab's choice). The party
-- side also stands down under the Party Frames kit and while target frames sit along
-- the stack; a saved choice that cannot apply stays saved.
function mod.RF_CompactOn(cfg, party)
    if not cfg or not (party and cfg.partyCompactMode == true or not party and cfg.raidCompactMode == true) then
        return false
    end
    local style = cfg
    if party and cfg == saved.profile then
        style = mod._partyProxy
    elseif party and cfg == mod._pvOverlayProxy then
        style = mod._scaledPartyProxy
    end
    if not mod.RF_CompactEligible(style) then
        return false
    end
    return not party or (not mod.RF_PartyKit() and not mod.PT_AlongStack(cfg, cfg.partyShowTargets == true))
end

-- The options pages' check for the tab they show (party: the Party tab).
function mod.RF_CompactOnTab(party)
    return mod.RF_CompactOn(party and mod._partyProxy or saved.profile, party)
end

function mod.RF_GridOn(cfg)
    return cfg.raidGridMode == true and mod.RF_CompactOn(cfg, false)
end

-- One physical pixel at the container's scale.
function mod.RF_OnePixel(party)
    local widget = party and mod._partyContainerFrame or boxHolder
    return CUI.PP.perfect / (widget and widget:GetEffectiveScale() or UIParent:GetEffectiveScale())
end

-- The spacing the layout uses: one pixel under the mode, else the saved slider value.
function mod.RF_CellSpacing(cfg, party)
    if mod.RF_CompactOn(cfg, party) then
        return mod.RF_OnePixel(party)
    end
    return PixelSnap(party and (cfg.partyCellSpacing or cfg.cellSpacing or 2) or (cfg.cellSpacing or 2))
end

function mod.RF_GroupSpacing(cfg)
    return mod.RF_GridOn(cfg) and mod.RF_OnePixel(false) or PixelSnap(cfg.groupSpacing or 8)
end

-------------------------------------------------------------------------------
--  Per-frame borders under the mode: the frame's own border stands down for the
--  shared outline, and hover and target draw a solid border of their own size.
-------------------------------------------------------------------------------
function mod.RF_ButtonCompact(skinData, s)
    return not skinData._isExtra and mod.RF_CompactOn(s, skinData._isParty == true)
end

-- A grouped pet: a header pet while its tab's mode is on, or a grouped preview pet.
function mod.RF_PetCompactOn(btnFrame, s)
    local skinData = FFD[btnFrame]
    if not skinData then
        return false
    end
    if skinData._petGroupedPreview then
        return mod.RF_CompactOn(s, skinData._petPreviewParty)
    end
    local popFrame = mod._PF
    return skinData._petHeader and popFrame and popFrame.active and mod.RF_CompactOn(s, popFrame.styleCtx == "party")
        or false
end

function mod.RF_PetCompactHighlight(btnFrame, s)
    local skinData = GetFFD(btnFrame)
    skinData._hovered, skinData._isTarget = mod._FB.hov[btnFrame], mod._FB.tgt[btnFrame]
    mod.RF_CompactHighlight(btnFrame._borderFrame, skinData, s, btnFrame)
end

function mod.RF_CompactHighlight(widget, skinData, cfg, btnFrame)
    local c, a, size, px
    if skinData._hovered and cfg.hoverBorderEnabled ~= false then
        c, a, size =
            cfg.hoverBorderColor or defaultSet.profile.hoverBorderColor,
            cfg.hoverBorderAlpha or 1,
            cfg.hoverBorderSize or 1
        px = CUI.BorderPx(cfg.hoverBorderSizePx, size, "solid")
    elseif skinData._isTarget and cfg.targetBorderEnabled ~= false then
        c, a, size =
            cfg.targetBorderColor or defaultSet.profile.targetBorderColor,
            cfg.targetBorderAlpha or 1,
            cfg.targetBorderSize or 1
        px = CUI.BorderPx(cfg.targetBorderSizePx, size, "solid")
    end
    solidStyle = solidStyle or { borderTexture = "solid" }
    if c then
        local red, green, blue = mod.RF_VisibleHighlight(cfg, c.r, c.g, c.b)
        local level = cfg.borderBehind and math.max(0, btnFrame:GetFrameLevel() - 1)
            or btnFrame:GetFrameLevel() + mod.LVL_RAISE
        if widget:GetFrameLevel() ~= level then
            widget:SetFrameLevel(level)
        end
        mod.ApplyHighlightBorder(widget, solidStyle, size, red, green, blue, a, px)
        local strips = CUI.PP.GetBorders(widget)
        if strips and strips:GetFrameLevel() ~= level + 1 then
            strips:SetFrameLevel(level + 1)
        end
    else
        mod.ApplyHighlightBorder(widget, solidStyle, nil, 0, 0, 0, 0)
    end
end

-------------------------------------------------------------------------------
--  Shared outlines. A state is one set of frames (the live raid, party or pet
--  header, or an options preview): its cells (each frame's rect), the style its
--  pieces draw in, and its pooled pieces -- outline hosts, separators and Grid
--  Mode's empty backgrounds. Draw runs only when a cell or the style changed,
--  and a piece takes the style again only when the style changed since it last
--  did (styleGen), so a roster change only moves pieces.
-------------------------------------------------------------------------------
local raid, party, pets, raidPreview, partyPreview, petPreview

local function HideState(st)
    if not st or not st.shown then
        return
    end
    for _, owner in ipairs(st.hosts) do
        if owner:IsShown() then
            CUI.HideBorderStyle(owner)
            owner:Hide()
            owner._sg = nil
        end
    end
    for _, frame in ipairs(st.empty) do
        if frame:IsShown() then
            frame:Hide()
        end
    end
    for _, t in ipairs(st.seams) do
        if t:IsShown() then
            t:Hide()
        end
    end
    st.shown, st.dirty = false, true
end

local function NewState(ownerFrame, isParty)
    return {
        owner = ownerFrame,
        isParty = isParty,
        groups = {},
        hosts = {},
        empty = {},
        seams = {},
        style = {},
        styleGen = 0,
        dirty = true,
    }
end

local function PutStyle(st, key, value)
    if st.style[key] ~= value then
        st.style[key], st.dirty, st.styleDirty = value, true, true
    end
end

local function UpdateStyle(st, cfg)
    local color = cfg.borderColor or defaultSet.profile.borderColor
    local grid = not st.isParty and mod.RF_GridOn(cfg)
    local red, green, blue, a
    if grid and not st.isPet then
        if cfg.healthColorMode == "dark" then
            red, green, blue, a = CUI.GetDarkModeBg()
        else
            red, green, blue, a = mod.GetBgColor(nil, cfg)
        end
    end
    PutStyle(st, "tex", cfg.borderTexture)
    PutStyle(st, "size", cfg.borderSize or 1)
    PutStyle(st, "px", CUI.BorderPx(cfg.borderSizePx, cfg.borderSize or 1, cfg.borderTexture))
    PutStyle(st, "offX", cfg.borderTextureOffset)
    PutStyle(st, "offY", cfg.borderTextureOffsetY)
    PutStyle(st, "shiftX", cfg.borderTextureShiftX)
    PutStyle(st, "shiftY", cfg.borderTextureShiftY)
    PutStyle(st, "behind", cfg.borderBehind)
    PutStyle(st, "r", color.r)
    PutStyle(st, "g", color.g)
    PutStyle(st, "b", color.b)
    PutStyle(st, "a", cfg.borderAlpha or 1)
    PutStyle(st, "bgR", red)
    PutStyle(st, "bgG", green)
    PutStyle(st, "bgB", blue)
    PutStyle(st, "bgA", a)
    PutStyle(st, "one", CUI.PP.perfect / st.owner:GetEffectiveScale())
    PutStyle(st, "grid", grid)
    -- Textured Background on the empty backgrounds, as on the frames.
    PutStyle(st, "bgTex", grid and not st.isPet and mod.RF_TexBgPath(cfg) or false)
    PutStyle(st, "bgVert", grid and mod.RF_IsVerticalFill(cfg) or false)
end

-- Records frame f as the index-th cell of group gi (rect in the owner's scale, top-left).
local function Cell(st, gi, index, frame)
    local set = st.groups[gi]
    if not set then
        set = { cells = {} }
        st.groups[gi] = set
    end
    local cell = set.cells[index]
    if not cell then
        cell = {}
        set.cells[index] = cell
    end
    local scale = frame:GetEffectiveScale() / st.owner:GetEffectiveScale()
    local posX, posY, wid, hgt = frame:GetRect()
    if not posX or not posY then
        return false
    end
    posX, posY, wid, hgt = posX * scale, (posY + hgt) * scale, wid * scale, hgt * scale
    local level, strata = frame:GetFrameLevel(), frame:GetFrameStrata()
    if
        cell.frame ~= frame
        or cell.x ~= posX
        or cell.y ~= posY
        or cell.w ~= wid
        or cell.h ~= hgt
        or cell.level ~= level
        or cell.strata ~= strata
    then
        cell.frame, cell.x, cell.y, cell.w, cell.h = frame, posX, posY, wid, hgt
        cell.level, cell.strata = level, strata
        st.dirty = true
    end
    return true
end

-- Cells in screen order: left to right, then top to bottom.
local function Along(a, b)
    if a.x == b.x then
        return a.y > b.y
    end
    return a.x < b.x
end

local function FinishGroup(st, gi, total, growth)
    local set = st.groups[gi]
    if not set then
        set = { cells = {} }
        st.groups[gi] = set
    end
    if set.count ~= total then
        set.count, st.dirty = total, true
    end
    if set.growth ~= growth then
        set.growth, st.dirty = growth, true
    end
end

-- An outline host round one box (x, y: its top-left in the owner's scale).
local function Host(st, index, first, posX, posY, wid, hgt)
    local owner = st.hosts[index]
    if not owner then
        owner = CreateFrame("Frame", nil, st.owner)
        st.hosts[index] = owner
    end
    local val = st.style
    owner:SetFrameStrata(first.strata)
    -- Normal dispel strips can reach button + 14; shared edges sit above them.
    owner:SetFrameLevel(val.behind and math.max(0, first.level - 1) or first.level + mod.LVL_AURA + 2)
    owner:ClearAllPoints()
    owner:SetPoint("TOPLEFT", first.frame, "TOPLEFT", posX - first.x, posY - first.y)
    owner:SetSize(wid, hgt)
    if owner._sg ~= st.styleGen or owner._w ~= wid or owner._h ~= hgt then
        owner._sg, owner._w, owner._h = st.styleGen, wid, hgt
        CUI.ApplyBorderStyle(
            owner,
            val.size,
            val.r,
            val.g,
            val.b,
            val.a,
            val.tex,
            val.offX,
            val.offY,
            val.shiftX,
            val.shiftY,
            "unitframes",
            val.size,
            nil,
            val.px
        )
    end
    owner:Show()
end

-- A separator along one join (x, y: the join's top-left in the owner's scale).
local function Seam(st, index, first, posX, posY, length, vertical)
    local t = st.seams[index]
    if not t then
        if not st.seamHost then
            st.seamHost = CreateFrame("Frame", nil, st.owner)
        end
        t = st.seamHost:CreateTexture(nil, "OVERLAY")
        CUI.PP.DisablePixelSnap(t)
        st.seams[index] = t
    end
    local val = st.style
    local owner = st.seamHost
    local level = val.behind and math.max(0, first.level - 1) or first.level + mod.LVL_AURA + 2
    if owner._level ~= level or owner._strata ~= first.strata then
        owner._level, owner._strata = level, first.strata
        owner:SetFrameStrata(first.strata)
        owner:SetFrameLevel(level)
    end
    if t._sg ~= st.styleGen or t._vertical ~= vertical then
        t._sg, t._vertical = st.styleGen, vertical
        t:SetDrawLayer("OVERLAY", vertical and 0 or 1)
        t:SetTexture(vertical and val.sepV or val.sepH)
        t:SetTexCoord(0, 1, 0, 1)
        t:SetVertexColor(val.r, val.g, val.b, val.a)
    end
    t:ClearAllPoints()
    t:SetPoint(
        "TOPLEFT",
        first.frame,
        "TOPLEFT",
        posX - first.x - (vertical and val.lead or 0),
        posY - first.y + (vertical and 0 or val.lead)
    )
    t:SetSize(vertical and val.thick or length, vertical and length or val.thick)
    t:Show()
end

local function Draw(st)
    if not st.dirty then
        return
    end
    local val = st.style
    if st.styleDirty then
        st.styleDirty = false
        st.styleGen = st.styleGen + 1
        local scale = st.owner:GetEffectiveScale()
        val.thick = CUI.BorderCompanionThickness(val.tex, val.size, val.px, scale)
        -- Both separator textures put their bright line at texel 5 of 32.
        val.lead = CUI.PP.SnapForES(val.thick * 5 / 32, scale)
        val.sepV, val.sepH = CUI.GetBorderCompanion(val.tex, "sepV"), CUI.GetBorderCompanion(val.tex, "sepH")
    end
    local gap = st.layoutPixel or val.one
    local hostCount, emptyCount, seamCount = 0, 0, 0
    local minX, maxY, maxX, minY, area, first = nil, nil, nil, nil, 0, nil
    for gi = 1, st.count do
        local set = st.groups[gi]
        local cells, num = set.cells, set.count
        if num > 0 then
            -- Keep the capture order stable so an unchanged UP/LEFT stack stays cached.
            set.sorted = set.sorted or {}
            for index = 1, num do
                set.sorted[index] = cells[index]
            end
            for index = #set.sorted, num + 1, -1 do
                set.sorted[index] = nil
            end
            table.sort(set.sorted, Along)
            cells = set.sorted
            local c = cells[1]
            local horizontal = set.growth == "LEFT" or set.growth == "RIGHT"
            local posX, posY = c.x, c.y
            local wid = horizontal and (num * c.w + (num - 1) * gap) or c.w
            local hgt = horizontal and c.h or (num * c.h + (num - 1) * gap)
            -- Grid Mode: an occupied group fills to five with empty backgrounds past
            -- its last frame along its growth.
            if val.grid and not st.isPet and num < 5 then
                local missing = 5 - num
                if set.growth == "LEFT" then
                    posX = posX - missing * (c.w + gap)
                end
                if set.growth == "UP" then
                    posY = posY + missing * (c.h + gap)
                end
                wid = horizontal and (5 * c.w + 4 * gap) or c.w
                hgt = horizontal and c.h or (5 * c.h + 4 * gap)
                for index = num + 1, 5 do
                    emptyCount = emptyCount + 1
                    local frame = st.empty[emptyCount]
                    if not frame then
                        frame = CreateFrame("Frame", nil, st.owner)
                        frame.bg = frame:CreateTexture(nil, "BACKGROUND")
                        frame.bg:SetAllPoints()
                        CUI.PP.DisablePixelSnap(frame.bg)
                        st.empty[emptyCount] = frame
                    end
                    local off = index - num
                    local endCell = (set.growth == "UP" or set.growth == "LEFT") and cells[1] or cells[num]
                    local dx = horizontal and off * (c.w + gap) * (set.growth == "LEFT" and -1 or 1) or 0
                    local dy = not horizontal and off * (c.h + gap) * (set.growth == "UP" and 1 or -1) or 0
                    frame:ClearAllPoints()
                    frame:SetPoint("TOPLEFT", endCell.frame, "TOPLEFT", dx, dy)
                    frame:SetSize(c.w, c.h)
                    frame:SetFrameStrata(c.strata)
                    frame:SetFrameLevel(c.level)
                    if frame._sg ~= st.styleGen then
                        frame._sg = st.styleGen
                        mod.RF_TexBgTint(frame.bg, val.bgTex or nil, val.bgVert)
                        frame.bg:SetColorTexture(val.bgR, val.bgG, val.bgB, val.bgA)
                    end
                    frame:Show()
                end
                num = 5
            end
            set.x, set.y, set.w, set.h = posX, posY, wid, hgt
            minX, maxY = math.min(minX or posX, posX), math.max(maxY or posY, posY)
            maxX, minY =
                math.max(maxX or (posX + wid), posX + wid), math.min(minY or (posY - hgt), posY - hgt)
            area = area + (wid + gap) * (hgt + gap)
            first = first or c
            for index = 1, num - 1 do
                seamCount = seamCount + 1
                Seam(
                    st,
                    seamCount,
                    c,
                    horizontal and posX + index * (c.w + gap) or posX,
                    horizontal and posY or posY - index * (c.h + gap),
                    horizontal and hgt or wid,
                    horizontal
                )
            end
        end
    end
    -- One outline round the groups only while they tile a rectangle (their padded
    -- areas fill the bounding box); any other shape keeps an outline per group.
    local rectangular = first
        and val.grid
        and math.abs(area - (maxX - minX + gap) * (maxY - minY + gap)) < gap * gap / 2
    if rectangular then
        hostCount = 1
        Host(st, 1, first, minX, maxY, maxX - minX, maxY - minY)
    end
    for gi = 1, st.count do
        local set = st.groups[gi]
        if set.count > 0 then
            if not rectangular then
                hostCount = hostCount + 1
                Host(st, hostCount, set.sorted[1], set.x, set.y, set.w, set.h)
            else
                -- Separators where two joined groups meet, along their shared length.
                for gj = gi + 1, st.count do
                    local other = st.groups[gj]
                    if other.count > 0 then
                        local posX = math.max(set.x, other.x)
                        local posY = math.min(set.y, other.y)
                        local width = math.min(set.x + set.w, other.x + other.w) - posX
                        local height = posY - math.max(set.y - set.h, other.y - other.h)
                        if
                            height > 0
                            and (
                                math.abs(set.x + set.w + gap - other.x) < gap / 2
                                or math.abs(other.x + other.w + gap - set.x) < gap / 2
                            )
                        then
                            seamCount = seamCount + 1
                            Seam(st, seamCount, first, posX, posY, height, true)
                        elseif
                            width > 0
                            and (
                                math.abs(set.y - set.h - gap - other.y) < gap / 2
                                or math.abs(other.y - other.h - gap - set.y) < gap / 2
                            )
                        then
                            seamCount = seamCount + 1
                            Seam(st, seamCount, first, posX, posY, width, false)
                        end
                    end
                end
            end
        end
    end
    for index = hostCount + 1, #st.hosts do
        local owner = st.hosts[index]
        if owner:IsShown() then
            CUI.HideBorderStyle(owner)
            owner:Hide()
            owner._sg = nil
        end
    end
    for index = emptyCount + 1, #st.empty do
        if st.empty[index]:IsShown() then
            st.empty[index]:Hide()
        end
    end
    for index = seamCount + 1, #st.seams do
        if st.seams[index]:IsShown() then
            st.seams[index]:Hide()
        end
    end
    st.shown, st.dirty = first ~= nil, false
end

-------------------------------------------------------------------------------
--  Live states. Hooks on the unit buttons queue a redraw, flushed once by a
--  hidden frame's one-shot OnUpdate in the same frame, after the header's own
--  pass and before the render.
-------------------------------------------------------------------------------
local RefreshLive, flusher
local function Flush(self)
    self:Hide()
    if raid and raid.pending then
        RefreshLive(raid)
    end
    if party and party.pending then
        RefreshLive(party)
    end
    if pets and pets.pending then
        RefreshLive(pets)
    end
end

local function Queue(st)
    if not st.on or st.pending then
        return
    end
    st.pending = true
    if not flusher then
        flusher = CreateFrame("Frame")
        flusher:Hide()
        flusher:SetScript("OnUpdate", Flush)
    end
    flusher:Show()
end

local function Hook(st, frame)
    if st.hooked[frame] then
        return
    end
    st.hooked[frame] = true
    frame:HookScript("OnShow", st.queue)
    frame:HookScript("OnHide", st.queue)
    frame:HookScript("OnSizeChanged", st.queue)
    frame:HookScript("OnAttributeChanged", st.assigned)
end

-- A mode turning on or off restyles the frames' own borders, threat and dispel rings.
local function RefreshButtonBorders(st, enabled)
    local changed = false
    for _, frame in ipairs(st.isParty and mod._partyAllButtons or allButtons) do
        local skinData = GetFFD(frame)
        if
            not skinData._isExtra
            and skinData.UpdateBorder
            and (enabled or skinData._compactBorder)
            and skinData._compactBorder ~= enabled
        then
            skinData.UpdateBorder()
            changed = true
            local unitToken = frame:GetAttribute("unit")
            if unitToken then
                mod.RF_PaintThreat(skinData, st.isParty and mod._scaledPartyProxy or mod._scaledProfile, unitToken)
            end
        end
    end
    if changed and mod.RFC_ReloadAll then
        mod.RFC_ReloadAll()
    end
end

local function CollectGroup(st, frameList, start, limit, gi, growth)
    local num = 0
    for index = start, limit do
        local frame = frameList and frameList[index]
        if frame then
            Hook(st, frame)
            if frame:IsVisible() and frame:GetAttribute("unit") and Cell(st, gi, num + 1, frame) then
                num = num + 1
            end
        end
    end
    FinishGroup(st, gi, num, growth)
end

local function HeaderGrowth(header)
    local anchorPoint = header and header:GetAttribute("point")
    return anchorPoint == "BOTTOM" and "UP"
        or anchorPoint == "LEFT" and "RIGHT"
        or anchorPoint == "RIGHT" and "LEFT"
        or "DOWN"
end

local function CollectLive(st, cfg)
    local total = 0
    if st.isPet then
        local popFrame = mod._PF
        local growth = HeaderGrowth(popFrame.container)
        for gi = 1, math.ceil(#popFrame.buttons / 5) do
            CollectGroup(
                st,
                popFrame.buttons,
                (gi - 1) * 5 + 1,
                math.min(gi * 5, #popFrame.buttons),
                gi,
                growth
            )
            total = gi
        end
    elseif st.isParty then
        CollectGroup(st, mod._partyAllButtons, 1, #mod._partyAllButtons, 1, mod._PartyGrowth(cfg))
        total = 1
    elseif cfg.mergeGroups then
        st.flat = st.flat or {}
        local limit = 0
        for index = 1, 40 do
            local frame = mod._flatHeader and mod._flatHeader[index]
            if frame then
                Hook(st, frame)
                if frame:IsVisible() and frame:GetAttribute("unit") then
                    limit = limit + 1
                    st.flat[limit] = frame
                end
            end
        end
        local growth = HeaderGrowth(mod._flatHeader)
        for gi = 1, math.ceil(limit / 5) do
            local num = 0
            for index = (gi - 1) * 5 + 1, math.min(gi * 5, limit) do
                if Cell(st, gi, num + 1, st.flat[index]) then
                    num = num + 1
                end
            end
            FinishGroup(st, gi, num, growth)
            total = gi
        end
    else
        for gi = 1, 8 do
            local heading = separatedHdrs[gi]
            CollectGroup(st, heading, 1, 5, gi, HeaderGrowth(heading))
        end
        total = 8
    end
    if st.count ~= total then
        st.count, st.dirty = total, true
    end
end

-- The settings a live state draws from.
local function StateSource(st)
    if st.isPet then
        return mod._PF.StyleSource()
    end
    return st.isParty and mod._partyProxy or saved.profile
end

RefreshLive = function(st)
    st.pending = nil
    if not st.on then
        return
    end
    local s = StateSource(st)
    UpdateStyle(st, s)
    CollectLive(st, s)
    Draw(st)
end

local function NewLiveState(ownerFrame, isParty)
    local st = NewState(ownerFrame, isParty)
    st.hooked = setmetatable({}, { __mode = "k" })
    st.queue = function()
        Queue(st)
    end
    st.assigned = function(_, name)
        if name == "unit" then
            Queue(st)
        end
    end
    return st
end

-- Called at the end of every raid and party layout pass.
function mod.RF_SyncCompact(isParty)
    local s = isParty and mod._partyProxy or saved.profile
    local enabled = mod.RF_CompactOn(s, isParty)
    local st
    if isParty then
        st = party
    else
        st = raid
    end
    if not enabled and not st then
        return
    end
    if enabled and not st then
        st = NewLiveState(isParty and mod._partyContainerFrame or boxHolder, isParty)
        if isParty then
            party = st
        else
            raid = st
        end
    end
    local wasOn = st.on
    st.on = enabled
    if wasOn ~= enabled then
        RefreshButtonBorders(st, enabled)
    end
    if enabled then
        st.layoutPixel = mod.RF_OnePixel(isParty)
        Queue(st)
    else
        HideState(st)
    end
end

-- Called at the end of every pet layout pass and when the pet header stands down.
function mod.RF_SyncPetCompact()
    local popFrame = mod._PF
    local isParty = popFrame and popFrame.styleCtx == "party"
    local enabled = popFrame and popFrame.active and mod.RF_CompactOn(popFrame.StyleSource(), isParty)
        or false
    local st = pets
    if not enabled and not st then
        return
    end
    if not st then
        st = NewLiveState(popFrame.container, isParty)
        st.isPet = true
        pets = st
    end
    if st.on ~= enabled then
        st.on = enabled
        for _, frame in ipairs(popFrame.buttons) do
            local skinData = GetFFD(frame)
            if frame._borderFrame and (enabled or skinData._petCompactBorder) and skinData._petCompactBorder ~= enabled then
                mod._FB.StyleBorder(frame)
            end
        end
    end
    st.isParty = isParty
    if enabled then
        st.layoutPixel = mod.RF_OnePixel(isParty)
        Queue(st)
    else
        HideState(st)
    end
end

-------------------------------------------------------------------------------
--  A new pixel grid (UI_SCALE_CHANGED, DISPLAY_SIZE_CHANGED and CUI's own UI
--  Scale, all through ns.RFC_PixelGridChanged): a live mode whose one pixel
--  moved re-lays its frames, at once out of combat and when combat ends in it,
--  and an attached boss group takes the new pitch (ns.FB_Repitch).
-------------------------------------------------------------------------------
local function Rescale(st)
    if not (st and st.on) or (st.isPet and not mod._PF.active) then
        return
    end
    if not mod.RF_CompactOn(StateSource(st), st.isParty) or st.layoutPixel == mod.RF_OnePixel(st.isParty) then
        return
    end
    if InCombatLockdown() then
        mod.CombatQueue.Defer(
            st.isPet and "compact-pet-scale" or st.isParty and "compact-party-scale" or "compact-raid-scale",
            function()
                Rescale(st)
            end
        )
        return
    end
    if st.isPet then
        mod._PF.Layout()
    elseif st.isParty then
        mod._LayoutPartyFrames()
    else
        Inner.LayoutGroups()
    end
end

function mod.RF_CompactScaleChanged()
    Rescale(raid)
    Rescale(party)
    Rescale(pets)
    mod.FB_Repitch()
end

-------------------------------------------------------------------------------
--  Options previews: the same pieces over the preview frames (party: the party
--  preview; growth: the preview's unit growth).
-------------------------------------------------------------------------------
local function PreviewCompact(st, frameList, s, isParty, growth, isPet)
    if not frameList or not mod.RF_CompactOn(s, isParty) then
        HideState(st)
        return st
    end
    local ownerFrame
    for _, frame in ipairs(frameList) do
        if frame:IsShown() then
            ownerFrame = frame:GetParent()
            break
        end
    end
    if not ownerFrame then
        HideState(st)
        return st
    end
    if not st then
        st = NewState(ownerFrame, isParty)
    end
    st.isPet, st.isParty = isPet, isParty
    if st.owner ~= ownerFrame then
        st.owner, st.dirty = ownerFrame, true
        for _, frame in ipairs(st.hosts) do
            frame:SetParent(ownerFrame)
        end
        for _, frame in ipairs(st.empty) do
            frame:SetParent(ownerFrame)
        end
        if st.seamHost then
            st.seamHost:SetParent(ownerFrame)
        end
    end
    UpdateStyle(st, s)
    local total = isParty and 1 or math.ceil(#frameList / 5)
    for gi = 1, total do
        local num = 0
        for index = (gi - 1) * 5 + 1, math.min(gi * 5, #frameList) do
            local frame = frameList[index]
            if frame:IsShown() and Cell(st, gi, num + 1, frame) then
                num = num + 1
            end
        end
        FinishGroup(st, gi, num, growth)
    end
    if st.count ~= total then
        st.count, st.dirty = total, true
    end
    Draw(st)
    return st
end

function mod.RF_PreviewCompact(frameList, s, isParty, growth)
    if isParty then
        partyPreview = PreviewCompact(partyPreview, frameList, s, true, growth)
    else
        raidPreview = PreviewCompact(raidPreview, frameList, s, false, growth)
    end
end

function mod.RF_PreviewPetCompact(frameList, s, isParty, growth)
    petPreview = PreviewCompact(petPreview, frameList, s, isParty, growth, true)
end

Inner.broken = false
