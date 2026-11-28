if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_GuideWindow.lua  (WoW Forever only)
--  Guide Window: RestedXP's levelling guide in one CludesUI window, in place
--  of RestedXP's own guide and active-steps frames:
--    the guide's name (its level range in the accent colour) and a progress
--    bar; the active steps, each in its box with its objectives (done ones
--    faded, counts like 3/12 coloured as they fill); the next steps in a
--    muted list. Shift-click a step to skip it (the active one) or go to it
--    (a later one); right-click opens RestedXP's menu; the - folds it.
--  RestedXP stays in charge: this only reads what it shows (its current
--  guide, active steps and its V2 step list) and calls its own SetStep and
--  menu. Its frames are faded out and kept from the mouse while this is on
--  and put back when it is off. Needs RestedXP with its V2 interface.
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature(
    "guideWindow",
    { enabled = false, width = 340, steps = 6, lock = false, folded = false, skip = "shift" },
    { point = "LEFT", relPoint = "LEFT", x = 20, y = 60 }
)
local Get, Enabled = F.Get, F.Enabled

local PAD, BOX_PAD, ROW_GAP, BAR_H = 10, 7, 3, 5
local ACTIVE_SHOWN = 3
local COUNT = "(%d+)%s*/%s*(%d+)"
local GREEN, AMBER = { 0.37, 0.77, 0.42 }, { 1, 0.7, 0.25 }

local window, silenced, watched, hooked = nil, {}, {}, {}
local started, pending = false, false
local rows, rowsUsed = {}, 0
local boxes, boxesUsed = {}, 0
local listCache

local function HasMethod(o, m) return type(o) == "table" and type(o[m]) == "function" end
local function DigField(t, ...)
    for i = 1, select("#", ...) do
        if type(t) ~= "table" then return nil end
        t = t[select(i, ...)]
    end
    return t
end
local reported = {}
local function CallSafely(name, fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn, ...)
    if ok then return result end
    if not reported[name] then
        reported[name] = true
        geterrorhandler()(result)
    end
end

local function RestedXP() return _G.RXP end
local function GuideReady()
    local v2 = DigField(RestedXP(), "v2")
    return HasMethod(v2, "IsGuideWindowEnabled") and v2:IsGuideWindowEnabled() and true or false
end

local function StripMarkup(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T[^|]*|t", ""):gsub("|A[^|]*|a", "")
    text = text:gsub("|H[^|]*|h", ""):gsub("|h", "")
    return (text:gsub("^%s+", ""))
end

-------------------------------------------------------------------------------
--  What RestedXP shows
-------------------------------------------------------------------------------

local function GuideHeading(rxp, guide)
    local title = guide.title or guide.subgroup or CallSafely("GuideName", rxp.GetGuideName, guide) or guide.name
    if type(title) ~= "string" then return "" end
    local range, place = title:match("^(%d+%-%d+)%s+(.+)$")
    if not range then place, range = title:match("^(.-)%s+(%d+%-%d+)$") end
    if range then return place .. "  " .. CUI.Kit.AccentHex() .. range .. "|r" end
    return title
end

local function ReadGuideStep(rxp, element)
    local frame = element.frame
    local textFs = DigField(frame, "text")
    local shown = HasMethod(textFs, "GetText") and textFs:GetText()
    if type(shown) ~= "string" or shown == "" or shown == " " then
        local raw = element.text ~= " " and element.text or element.tooltipText or element.rawtext
        shown = type(raw) == "string" and raw or ""
        shown = CallSafely("ReplaceNpc", rxp.ReplaceNpcIds, shown, element) or shown
    end
    local icon = DigField(frame, "icon")
    local glyph = HasMethod(icon, "GetText") and icon:GetText()
    if type(glyph) ~= "string" then glyph = element.icon or DigField(rxp, "icons", element.tag) or "" end
    local button = DigField(frame, "button")
    local done = (HasMethod(button, "GetChecked") and button:GetChecked()) or element.completed or element.skip
    local have, need = StripMarkup(shown):match(COUNT)
    if type(element.tag) == "string" and element.tag:find("^buy") and type(element.id) == "number" and type(element.qty) == "number" then
        have, need = C_Item.GetItemCount(element.id), element.qty
    end
    return { text = shown, icon = glyph, done = done and true or false, source = textFs, have = tonumber(have), need = tonumber(need) }
end

local function GuideSteps(rxp)
    local v2 = rxp.v2
    if not HasMethod(v2, "BuildGuideStepsSnapshot") then return {} end
    if listCache and listCache.guide == rxp.currentGuide then return listCache.list end
    local snapshot = CallSafely("Snapshot", v2.BuildGuideStepsSnapshot, v2, true)
    local list = {}
    for _, r in ipairs(snapshot and snapshot.rows or {}) do
        if not r.hidden and type(r.text) == "string" then
            list[#list + 1] = { index = r.index, text = StripMarkup(r.text:match("^[^\n]*") or ""), done = r.complete and true or false }
        end
    end
    listCache = { guide = rxp.currentGuide, list = list }
    return list
end

local function ReadGuide()
    local rxp = RestedXP()
    local guide = rxp and rxp.currentGuide
    if not guide or guide.empty then return nil end
    local model = { heading = GuideHeading(rxp, guide), steps = {} }
    local step = CallSafely("Progress", rxp.GetGuideProgress)
    local total = guide.steps and #guide.steps or 0
    if step and total > 0 then model.step, model.total = step, total end
    local after = step or 0
    for _, s in ipairs(DigField(rxp, "RXPFrame", "activeSteps") or {}) do
        if s.active and not s.hidewindow and not s.hidetip then
            local list = {}
            for _, element in ipairs(s.elements or {}) do
                if element.text or element.rawtext or element.tooltipText then list[#list + 1] = ReadGuideStep(rxp, element) end
            end
            local label = (s.title and s.title ~= "") and s.title or CUI.Lf("Step %1$d", s.index)
            model.steps[#model.steps + 1] = { label = label, rows = list, source = s }
            if s.index > after then after = s.index end
            if #model.steps == ACTIVE_SHOWN then break end
        end
    end
    model.next = {}
    for _, entry in ipairs(GuideSteps(rxp)) do
        if entry.index > after and #model.next < Get("steps") then model.next[#model.next + 1] = entry end
    end
    return model
end

-------------------------------------------------------------------------------
--  RestedXP's own frames, faded out while this is on
-------------------------------------------------------------------------------

local function MuteFrame(frame, top)
    if not frame or not frame.EnableMouse then return end
    if not silenced[frame] then
        local home = { mouse = frame:IsMouseEnabled() }
        silenced[frame] = home
        if top then
            home.alpha = frame:GetAlpha()
            frame:SetAlpha(0)
            if not watched[frame] then
                watched[frame] = true
                hooksecurefunc(frame, "SetAlpha", function(self, a)
                    if silenced[self] and a ~= 0 then self:SetAlpha(0) end
                end)
            end
        end
        frame:EnableMouse(false)
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        MuteFrame(child, false)
    end
end

local function TakeOverWindow()
    local rxp = RestedXP()
    local guide = DigField(_G.RXPV2GuideWindow, "frame")
    local steps = rxp and rxp.player and _G["RXPActiveStepsFrame" .. tostring(rxp.player.name)]
    steps = DigField(steps, "frame") or steps
    MuteFrame(guide, true)
    MuteFrame(steps, true)
end

local function RestoreWindow()
    for frame, home in pairs(silenced) do
        silenced[frame] = nil
        if home.alpha then frame:SetAlpha(home.alpha) end
        frame:EnableMouse(home.mouse)
    end
end

-------------------------------------------------------------------------------
--  The window
-------------------------------------------------------------------------------

local QueueRedraw

local function SkipAllowed()
    local mode = Get("skip")
    return mode == "click" or (mode == "shift" and IsShiftKeyDown())
end

local function Menu() CallSafely("Menu", DigField(RestedXP(), "RXPFrame", "DropDownMenu")) end

local function SkipStep(step)
    local rxp = RestedXP()
    local progress = CallSafely("Progress", rxp.GetGuideProgress)
    if not progress then return end
    if step and step.index ~= progress then
        for _, element in ipairs(step.elements or {}) do
            if not element.optional and not element.skip then
                element.skip = true
                if element.OnComplete then CallSafely("Complete", element.OnComplete, element) end
            end
        end
        rxp.updateSteps = true
        CallSafely("Map", rxp.UpdateMap)
    else
        CallSafely("SetStep", rxp.SetStep, progress + 1)
    end
end

local function ShowTip(owner, text)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:SetText(text, CUI.Kit.Accent())
    local mode = Get("skip")
    if mode == "shift" then GameTooltip:AddLine(CUI.L("Shift-click"), 0.7, 0.7, 0.7) end
    GameTooltip:AddLine(CUI.L("Right-click: menu"), 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

local function NewText(parent, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    CUI.Kit.Font(fs, size, "essentials")
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    if color then fs:SetTextColor(color[1], color[2], color[3]) end
    return fs
end

local function Build()
    if window then return window end
    local Kit = CUI.Kit
    window = CreateFrame("Frame", "CludesUIGuideWindow", UIParent)
    window:SetFrameStrata("MEDIUM")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", function(self)
        if not Get("lock") and not CUI._unlockActive then self:StartMoving() end
    end)
    window:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        if point then F.Cfg().pos = { point = point, relPoint = relPoint, x = x, y = y } end
    end)
    window:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then Menu() end
    end)
    Kit.Panel(window, 0.85)
    window.title = NewText(window, 14)
    window.title:SetPoint("TOPLEFT", PAD, -PAD)
    window.title:SetPoint("RIGHT", window, "RIGHT", -PAD - 20, 0)
    window.title:SetWordWrap(false)
    window.fold = Kit.Glyph(window, "-", function()
        F.Cfg().folded = not Get("folded")
        QueueRedraw()
    end, CUI.L("Fold"), "essentials")
    window.fold:SetPoint("TOPRIGHT", -5, -6)
    window.progress = NewText(window, Kit.SMALL_SIZE, Kit.Palette.muted)
    window.bar = CreateFrame("StatusBar", nil, window)
    window.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    window.bar:SetHeight(BAR_H)
    window.bar.bg = window.bar:CreateTexture(nil, "BACKGROUND")
    window.bar.bg:SetAllPoints()
    window.bar.bg:SetColorTexture(1, 1, 1, 0.08)
    Kit.Border(window.bar, 0, 0, 0, 1)
    return window
end

local function StepBox(i)
    local b = boxes[i]
    if b then return b end
    b = CreateFrame("Button", nil, window)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.edge = b:CreateTexture(nil, "BORDER")
    b.edge:SetPoint("TOPLEFT")
    b.edge:SetPoint("BOTTOMLEFT")
    b.edge:SetWidth(2)
    b.label = NewText(b, CUI.Kit.SMALL_SIZE)
    b.label:SetPoint("TOPLEFT", BOX_PAD, -BOX_PAD)
    b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then return Menu() end
        if SkipAllowed() then SkipStep(self.step) end
    end)
    b:SetScript("OnEnter", function(self) ShowTip(self, CUI.L("Skip step")) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    boxes[i] = b
    return b
end

local function StepLine(i)
    local fs = rows[i]
    if fs then return fs end
    fs = NewText(window, CUI.Kit.TEXT_SIZE)
    rows[i] = fs
    return fs
end

-- The next steps: one button each (shift-click goes there).
local nextRows = {}
local function NextStepRow(i)
    local r = nextRows[i]
    if r then return r end
    r = CreateFrame("Button", nil, window)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.text = NewText(r, CUI.Kit.SMALL_SIZE, CUI.Kit.Palette.muted)
    r.text:SetPoint("TOPLEFT")
    r.text:SetPoint("TOPRIGHT")
    r.text:SetWordWrap(false)
    r:SetScript("OnClick", function(self, button)
        if button == "RightButton" then return Menu() end
        if SkipAllowed() and self.index then CallSafely("SetStep", RestedXP().SetStep, self.index) end
    end)
    r:SetScript("OnEnter", function(self) ShowTip(self, CUI.Lf("Go to step %1$d", self.index or 0)) end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    nextRows[i] = r
    return r
end

-- A row's source text changing (an objective's count) redraws the window.
local function WatchSource(source)
    if source and not hooked[source] and HasMethod(source, "SetText") then
        hooked[source] = true
        hooksecurefunc(source, "SetText", function()
            if window and window:IsShown() then QueueRedraw() end
        end)
    end
end

local function Redraw()
    pending = false
    if not (Enabled() and RestedXP() and GuideReady()) then
        if window then window:Hide() end
        RestoreWindow()
        return
    end
    TakeOverWindow()
    Build()
    local Kit = CUI.Kit
    local width = Get("width")
    local inner = width - 2 * PAD
    window:SetWidth(width)
    local model = ReadGuide()
    window.title:SetText(model and model.heading or CUI.L("No guide selected"))
    window.fold.t:SetText(Get("folded") and "+" or "-")
    local y = -PAD - 18
    rowsUsed, boxesUsed = 0, 0
    if model and model.total then
        window.progress:ClearAllPoints()
        window.progress:SetPoint("TOPLEFT", PAD, y)
        window.progress:SetText(CUI.Lf("Step %1$d of %2$d  (%3$d%%)", model.step, model.total, math.floor(model.step / model.total * 100 + 0.5)))
        window.progress:Show()
        y = y - 14
        window.bar:ClearAllPoints()
        window.bar:SetPoint("TOPLEFT", PAD, y)
        window.bar:SetWidth(inner)
        window.bar:SetMinMaxValues(0, model.total)
        window.bar:SetValue(model.step)
        window.bar:GetStatusBarTexture():SetVertexColor(Kit.Accent())
        window.bar:Show()
        y = y - BAR_H - 8
    else
        window.progress:Hide()
        window.bar:Hide()
        y = y - 4
    end
    if model and not Get("folded") then
        local r, g, b = Kit.Accent()
        for _, step in ipairs(model.steps) do
            boxesUsed = boxesUsed + 1
            local box = StepBox(boxesUsed)
            box.step = step.source
            box.bg:SetColorTexture(r, g, b, boxesUsed == 1 and 0.12 or 0.06)
            box.edge:SetColorTexture(r, g, b, boxesUsed == 1 and 1 or 0.4)
            box.label:SetText(step.label)
            box.label:SetTextColor(r, g, b)
            box:ClearAllPoints()
            box:SetPoint("TOPLEFT", PAD, y)
            box:SetWidth(inner)
            local by = -BOX_PAD - box.label:GetStringHeight() - 4
            for _, row in ipairs(step.rows) do
                rowsUsed = rowsUsed + 1
                local fs = StepLine(rowsUsed)
                fs:SetParent(box)
                fs:ClearAllPoints()
                fs:SetPoint("TOPLEFT", box, "TOPLEFT", BOX_PAD, by)
                fs:SetWidth(inner - 2 * BOX_PAD)
                local text = row.text
                if row.icon ~= "" then text = row.icon .. " " .. text end
                fs:SetText(text)
                local c = Kit.Palette.text
                if row.done then
                    c = Kit.Palette.muted
                elseif row.have and row.need and row.need > 0 then
                    c = row.have >= row.need and GREEN or (row.have > 0 and AMBER or c)
                end
                fs:SetTextColor(c[1], c[2], c[3])
                fs:SetAlpha(row.done and 0.6 or 1)
                fs:Show()
                WatchSource(row.source)
                by = by - fs:GetStringHeight() - ROW_GAP
            end
            local h = -by + BOX_PAD - ROW_GAP
            box:SetHeight(h)
            box:Show()
            y = y - h - 6
        end
        for i, entry in ipairs(model.next) do
            local nr = NextStepRow(i)
            nr.index = entry.index
            nr.text:SetText(("%d. %s"):format(entry.index, entry.text))
            nr:ClearAllPoints()
            nr:SetPoint("TOPLEFT", PAD, y)
            nr:SetSize(inner, 14)
            nr:Show()
            y = y - 15
        end
        for i = #model.next + 1, #nextRows do
            nextRows[i]:Hide()
        end
    else
        for i = 1, #nextRows do
            nextRows[i]:Hide()
        end
    end
    for i = rowsUsed + 1, #rows do
        rows[i]:Hide()
    end
    for i = boxesUsed + 1, #boxes do
        boxes[i]:Hide()
    end
    window:SetHeight(-y + PAD - 4)
    if not window._placed then
        window._placed = true
        F.Place(window)
    end
    window:Show()
end

-- Many RestedXP updates land together: one redraw on the next frame.
function QueueRedraw()
    if pending then return end
    pending = true
    C_Timer.After(0, Redraw)
end

local function OnGuideRebuilt()
    listCache = nil
    QueueRedraw()
end

local function StartFollowing()
    if started or not RestedXP() then return end
    started = true
    local rxp = RestedXP()
    if HasMethod(rxp, "SetStep") then hooksecurefunc(rxp, "SetStep", OnGuideRebuilt) end
    local v2 = rxp.v2
    for _, name in ipairs({ "UpdateGuideWindow", "UpdateActiveStepsFrame", "UpdatePlayerActiveStepItem" }) do
        if HasMethod(v2, name) then hooksecurefunc(v2, name, OnGuideRebuilt) end
    end
end

local loader = CreateFrame("Frame")
loader:SetScript("OnEvent", function(_, evt, name)
    if evt == "ADDON_LOADED" and name ~= "RXPGuides" then return end
    loader:UnregisterEvent("ADDON_LOADED")
    StartFollowing()
    QueueRedraw()
end)

local function Apply()
    if Enabled() then
        if RestedXP() then
            StartFollowing()
        else
            loader:RegisterEvent("ADDON_LOADED")
        end
        if window and not CUI._unlockActive then F.Place(window) end
        OnGuideRebuilt()
    else
        if window then window:Hide() end
        RestoreWindow()
    end
end

CUI._GuideWindow = { Get = Get, Cfg = F.Cfg, Apply = Apply, Read = ReadGuide, Loaded = function() return RestedXP() ~= nil end, Ready = GuideReady }

F.Start(Apply, {
    key = "CUI_GuideWindow",
    label = "Guide Window",
    order = 762,
    frame = function(build)
        if build then Build() end
        return window
    end,
    size = function() return Get("width"), window and window:GetHeight() or 200 end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})
