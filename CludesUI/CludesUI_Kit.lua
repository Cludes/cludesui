if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI_Kit.lua
--  The house controls for module windows and on-screen frames, so every
--  feature looks like the rest of CludesUI: square panels with pixel-perfect
--  1 px borders (PP), the module's font and outline (ApplyModuleFont), and
--  the theme's accent (CLUDES_GREEN, read live, so a theme change follows).
--    Kit.Accent() / Kit.AccentHex() / Kit.SyncAccent(t)
--    Kit.Font(fs, size, key[, flags])      module font, size, outline
--    Kit.Panel(frame[, alpha])             dark fill and a black 1 px border
--    Kit.Window(name, w, h, title, opts)   a movable window: Panel, accent
--                                          title, flat close glyph, Escape
--    Kit.Button(parent, text, w, h, onClick[, opts])  flat square button
--    Kit.Glyph(parent, text, onClick[, tip])          bare header glyph
--    Kit.Check(parent, label, onClick)     square checkbox
--    Kit.Input(parent, w, h[, placeholder])           flat edit box
--    Kit.Scroll(parent)                    scroll frame with a thin bar
--    Kit.ContextMenu(owner, builder)       ShowContextMenu, fed by a
--                                          MenuUtil-style builder
--  opts.key is the font key (Forever Tools pass "essentials"; nil is the
--  global font).
-------------------------------------------------------------------------------
local Kit = {}
CludesUI.Kit = Kit

local BG = { 0.062, 0.070, 0.082 } -- the house popup fill
local CONTROL_BG = { 0, 0, 0, 0.5 }
local IDLE = { 0.82, 0.82, 0.82 }

local function Pix()
    return CludesUI.PP
end

function Kit.Accent()
    local color = CludesUI.CLUDES_GREEN
    if color then
        return color.r, color.g, color.b
    end
    return 0.30, 0.79, 0.94
end

function Kit.AccentHex()
    return CludesUI.HexColor(Kit.Accent())
end

--- Copies the accent into an { r, g, b } array the caller keeps (for colour
--- tables a feature passes around); returns it.
function Kit.SyncAccent(t)
    t[1], t[2], t[3] = Kit.Accent()
    return t
end

--- Colours a font string in the accent now and each time its frame shows.
function Kit.AccentText(fontStr, alpha)
    local function Paint()
        local red, green, blue = Kit.Accent()
        fontStr:SetTextColor(red, green, blue, alpha or 1)
    end
    Paint()
    local ownerFrame = fontStr:GetParent()
    if ownerFrame and ownerFrame.HookScript and not fontStr._kitAccent then
        ownerFrame:HookScript("OnShow", Paint)
    end
    fontStr._kitAccent = true
end

function Kit.Font(fontStr, size, key, flags)
    CludesUI.ApplyModuleFont(fontStr, nil, size, key, flags)
end

local function Border(widget, red, green, blue, a)
    local pp = Pix()
    if pp.GetBorders and pp.GetBorders(widget) then
        pp.SetBorderColor(widget, red, green, blue, a)
    else
        pp.CreateBorder(widget, red, green, blue, a, 1, "OVERLAY", 7)
    end
end
Kit.Border = Border

function Kit.Panel(widget, alpha)
    local backdrop = widget._kitBg
    if not backdrop then
        backdrop = widget:CreateTexture(nil, "BACKGROUND", nil, -8)
        backdrop:SetAllPoints()
        widget._kitBg = backdrop
    end
    backdrop:SetColorTexture(BG[1], BG[2], BG[3], alpha or 0.95)
    Border(widget, 0, 0, 0, 1)
    return widget
end

function Kit.Glyph(hostFrame, textValue, onClick, tipText, key)
    local b = CreateFrame("Button", nil, hostFrame)
    b:SetSize(18, 18)
    b.t = b:CreateFontString(nil, "OVERLAY")
    Kit.Font(b.t, 14, key)
    b.t:SetPoint("CENTER")
    b.t:SetText(textValue)
    b.t:SetTextColor(IDLE[1], IDLE[2], IDLE[3])
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        self.t:SetTextColor(Kit.Accent())
        if tipText then
            CludesUI.ShowWidgetTooltip(self, tipText)
        end
    end)
    b:SetScript("OnLeave", function(self)
        self.t:SetTextColor(IDLE[1], IDLE[2], IDLE[3])
        if tipText then
            CludesUI.HideWidgetTooltip()
        end
    end)
    return b
end

--- A movable window. opts: key (font), strata, special (false: Escape does
--- not close it), onClose. Fields: title, close, header (the line under the
--- title bar).
function Kit.Window(name, wid, hgt, title, options)
    options = options or {}
    local window = CreateFrame("Frame", name, UIParent)
    window:SetSize(wid, hgt)
    window:SetPoint("CENTER", 0, 30)
    window:SetFrameStrata(options.strata or "HIGH")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    Kit.Panel(window)
    window.title = window:CreateFontString(nil, "OVERLAY")
    Kit.Font(window.title, 15, options.key)
    window.title:SetPoint("TOPLEFT", 10, -8)
    window.title:SetText(title or "")
    window.header = window:CreateTexture(nil, "ARTWORK")
    window.header:SetHeight(1)
    window.header:SetPoint("TOPLEFT", 1, -28)
    window.header:SetPoint("TOPRIGHT", -1, -28)
    window.close = Kit.Glyph(window, "x", function()
        if options.onClose then
            options.onClose()
        end
        window:Hide()
    end, nil, options.key)
    window.close:SetPoint("TOPRIGHT", -5, -5)
    local function Paint()
        local red, green, blue = Kit.Accent()
        window.title:SetTextColor(red, green, blue)
        window.header:SetColorTexture(red, green, blue, 0.35)
    end
    Paint()
    window:HookScript("OnShow", Paint)
    if name and options.special ~= false then
        tinsert(UISpecialFrames, name)
    end
    return window
end

--- A flat square button. opts: key (font), size (text size), tip. Methods:
--- SetText, GetText, GetTextWidth, SetActive(bool) (the picked tab).
function Kit.Button(hostFrame, textValue, wid, hgt, onClick, options)
    options = options or {}
    local b = CreateFrame("Button", nil, hostFrame)
    b:SetSize(wid or 90, hgt or 22)
    local backdrop = b:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(CONTROL_BG[1], CONTROL_BG[2], CONTROL_BG[3], CONTROL_BG[4])
    b._bg = backdrop
    b.label = b:CreateFontString(nil, "OVERLAY")
    Kit.Font(b.label, options.size or 12, options.key)
    b.label:SetPoint("CENTER")
    b.label:SetText(textValue or "")
    local function Paint(hovered)
        local r, g, bl = Kit.Accent()
        local lit = hovered or b._active
        Border(b, r, g, bl, lit and 1 or 0.45)
        if b._active then
            b.label:SetTextColor(r, g, bl)
            backdrop:SetColorTexture(r, g, bl, 0.15)
        else
            b.label:SetTextColor(hovered and 1 or IDLE[1], hovered and 1 or IDLE[2], hovered and 1 or IDLE[3])
            backdrop:SetColorTexture(CONTROL_BG[1], CONTROL_BG[2], CONTROL_BG[3], CONTROL_BG[4])
        end
    end
    b._paint = Paint
    Paint(false)
    b:HookScript("OnEnter", function(self)
        Paint(true)
        if options.tip then
            CludesUI.ShowWidgetTooltip(self, options.tip)
        end
    end)
    b:HookScript("OnLeave", function()
        Paint(false)
        if options.tip then
            CludesUI.HideWidgetTooltip()
        end
    end)
    if onClick then
        b:SetScript("OnClick", onClick)
    end
    function b:SetText(t)
        self.label:SetText(t)
    end
    function b:GetText()
        return self.label:GetText()
    end
    function b:GetTextWidth()
        return self.label:GetStringWidth()
    end
    function b:SetActive(enabled)
        self._active = enabled and true or nil
        Paint(self:IsMouseOver())
    end
    b:HookScript("OnShow", function(self)
        Paint(self:IsMouseOver())
    end)
    return b
end

--- A square checkbox with its label. Methods: SetChecked, GetChecked,
--- SetLabel. onClick(self) runs after the box flips.
function Kit.Check(hostFrame, labelText, onClick, key)
    local c = CreateFrame("Button", nil, hostFrame)
    c:SetSize(16, 16)
    local backdrop = c:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(CONTROL_BG[1], CONTROL_BG[2], CONTROL_BG[3], CONTROL_BG[4])
    c.mark = c:CreateTexture(nil, "ARTWORK")
    c.mark:SetPoint("TOPLEFT", 3, -3)
    c.mark:SetPoint("BOTTOMRIGHT", -3, 3)
    c.text = c:CreateFontString(nil, "OVERLAY")
    Kit.Font(c.text, 12, key)
    c.text:SetPoint("LEFT", c, "RIGHT", 6, 0)
    c.text:SetText(labelText or "")
    c.text:SetTextColor(IDLE[1], IDLE[2], IDLE[3])
    local function Paint()
        local red, green, blue = Kit.Accent()
        Border(c, red, green, blue, c:IsMouseOver() and 1 or 0.6)
        c.mark:SetColorTexture(red, green, blue, 1)
        c.mark:SetShown(c._checked == true)
    end
    function c:SetChecked(enabled)
        self._checked = enabled and true or false
        Paint()
    end
    function c:GetChecked()
        return self._checked == true
    end
    function c:SetLabel(t)
        self.text:SetText(t)
    end
    -- The flip is on PreClick, so a caller's own OnClick (SetScript) keeps it.
    c:SetScript("PreClick", function(self)
        self:SetChecked(not self._checked)
    end)
    if onClick then
        c:SetScript("OnClick", onClick)
    end
    c:SetScript("OnEnter", Paint)
    c:SetScript("OnLeave", Paint)
    c:SetChecked(false)
    return c
end

--- A flat edit box with a grey placeholder while empty and unfocused.
function Kit.Input(hostFrame, wid, hgt, placeholder, key)
    local e = CreateFrame("EditBox", nil, hostFrame)
    e:SetSize(wid or 160, hgt or 22)
    e:SetAutoFocus(false)
    e:SetTextInsets(6, 6, 0, 0)
    local backdrop = e:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(CONTROL_BG[1], CONTROL_BG[2], CONTROL_BG[3], CONTROL_BG[4])
    Kit.Font(e, 12, key)
    e:SetTextColor(1, 1, 1)
    e.hint = e:CreateFontString(nil, "OVERLAY")
    Kit.Font(e.hint, 12, key)
    e.hint:SetPoint("LEFT", 6, 0)
    e.hint:SetTextColor(0.5, 0.5, 0.5)
    e.hint:SetText(placeholder or "")
    local function Paint()
        local red, green, blue = Kit.Accent()
        Border(e, red, green, blue, e:HasFocus() and 1 or 0.45)
        e.hint:SetShown(e:GetText() == "" and not e:HasFocus())
    end
    e:HookScript("OnEditFocusGained", Paint)
    e:HookScript("OnEditFocusLost", Paint)
    e:HookScript("OnTextChanged", Paint)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:SetScript("OnEnterPressed", e.ClearFocus)
    Paint()
    return e
end

--- A scroll frame filling parent between insets, with a thin accent bar on
--- its right that shows only when there is more to scroll. Returns scroll,
--- content (content's width follows the scroll frame's).
function Kit.Scroll(hostFrame)
    local scroll = CreateFrame("ScrollFrame", nil, hostFrame)
    local contentFrame = CreateFrame("Frame", nil, scroll)
    contentFrame:SetSize(1, 1)
    scroll:SetScrollChild(contentFrame)
    local track = CreateFrame("Frame", nil, hostFrame)
    track:SetWidth(4)
    track:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
    track:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
    local trackTex = track:CreateTexture(nil, "BACKGROUND")
    trackTex:SetAllPoints()
    trackTex:SetColorTexture(1, 1, 1, 0.06)
    local thumb = CreateFrame("Frame", nil, track)
    thumb:SetWidth(4)
    thumb:EnableMouse(true)
    local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
    thumbTex:SetAllPoints()

    local function Update()
        local range = scroll:GetVerticalScrollRange() or 0
        local hgt = scroll:GetHeight() or 0
        if range <= 0.5 or hgt <= 0 then
            track:Hide()
            if scroll:GetVerticalScroll() ~= 0 then
                scroll:SetVerticalScroll(0)
            end
            return
        end
        track:Show()
        local red, green, blue = Kit.Accent()
        thumbTex:SetColorTexture(red, green, blue, 0.7)
        local th = math.max(20, hgt * hgt / (hgt + range))
        thumb:SetHeight(th)
        local place = (scroll:GetVerticalScroll() / range) * (hgt - th)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -place)
    end

    local function ScrollTo(val)
        local range = scroll:GetVerticalScrollRange() or 0
        scroll:SetVerticalScroll(math.max(0, math.min(range, val)))
        Update()
    end

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        ScrollTo(self:GetVerticalScroll() - delta * 40)
    end)
    scroll:SetScript("OnScrollRangeChanged", Update)
    scroll:SetScript("OnVerticalScroll", Update)
    scroll:SetScript("OnSizeChanged", function(self, wid)
        contentFrame:SetWidth(wid)
        Update()
    end)
    thumb:SetScript("OnMouseDown", function(self)
        local _, curY = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        self._startY, self._startV = curY / scale, scroll:GetVerticalScroll()
        self:SetScript("OnUpdate", function(s)
            local _, posY = GetCursorPosition()
            posY = posY / scale
            local range = scroll:GetVerticalScrollRange() or 0
            local hgt = scroll:GetHeight() - s:GetHeight()
            if hgt > 0 then
                ScrollTo(s._startV + (s._startY - posY) / hgt * range)
            end
        end)
    end)
    thumb:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    scroll.Refresh = Update
    track:Hide()
    return scroll, contentFrame
end

-------------------------------------------------------------------------------
--  Context menu: CludesUI's own (ShowContextMenu), built from a MenuUtil-style
--  builder so a feature can describe it the same way:
--    root:CreateTitle(text)              root:CreateDivider()
--    root:CreateButton(text, fn)         returns a node for sub-items
--    root:CreateRadio(text, isOn, fn)    root:CreateCheckbox(text, isOn, fn)
--  Texts are shown as given (player and spell names are not translated).
-------------------------------------------------------------------------------
local Node = {}
Node.__index = Node

local function NewNode()
    return setmetatable({ items = {} }, Node)
end

function Node:CreateTitle(textValue)
    table.insert(self.items, {
        text = textValue,
        noLoc = true,
        isDisabled = function()
            return true
        end,
    })
end
function Node:CreateDivider()
    if #self.items > 0 then
        table.insert(self.items, "---")
    end
end
function Node:CreateButton(textValue, func)
    local childFrame = NewNode()
    local item = { text = textValue, noLoc = true, onClick = func }
    item._node = childFrame
    table.insert(self.items, item)
    return childFrame
end
function Node:CreateRadio(textValue, isOn, func)
    table.insert(
        self.items,
        { text = textValue, noLoc = true, isActive = isOn and isOn() or false, onClick = func }
    )
end
Node.CreateCheckbox = Node.CreateRadio

local function Items(node)
    local result = {}
    for _, item in ipairs(node.items) do
        if type(item) == "table" and item._node then
            local kids = Items(item._node)
            local copy = { text = item.text, noLoc = true, onClick = item.onClick }
            if #kids > 0 then
                copy.children, copy.onClick = kids, nil
            end
            result[#result + 1] = copy
        else
            result[#result + 1] = item
        end
    end
    if result[#result] == "---" then
        result[#result] = nil
    end
    return result
end

function Kit.ContextMenu(ownerFrame, builder, options)
    local root = NewNode()
    builder(ownerFrame, root)
    CludesUI.ShowContextMenu(ownerFrame, Items(root), options)
end
