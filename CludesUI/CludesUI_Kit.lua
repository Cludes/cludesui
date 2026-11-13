if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
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

local BG = { 0.077, 0.068, 0.058 }       -- the house popup fill
local CONTROL_BG = { 0, 0, 0, 0.5 }
local IDLE = { 0.82, 0.82, 0.82 }

local function PP() return CludesUI.PP end

function Kit.Accent()
    local c = CludesUI.CLUDES_GREEN
    if c then return c.r, c.g, c.b end
    return 0.30, 0.79, 0.94
end

function Kit.AccentHex() return CludesUI.HexColor(Kit.Accent()) end

--- Copies the accent into an { r, g, b } array the caller keeps (for colour
--- tables a feature passes around); returns it.
function Kit.SyncAccent(t)
    t[1], t[2], t[3] = Kit.Accent()
    return t
end

--- Colours a font string in the accent now and each time its frame shows.
function Kit.AccentText(fs, alpha)
    local function Paint()
        local r, g, b = Kit.Accent()
        fs:SetTextColor(r, g, b, alpha or 1)
    end
    Paint()
    local owner = fs:GetParent()
    if owner and owner.HookScript and not fs._kitAccent then owner:HookScript("OnShow", Paint) end
    fs._kitAccent = true
end

function Kit.Font(fs, size, key, flags)
    CludesUI.ApplyModuleFont(fs, nil, size, key, flags)
end

local function Border(frame, r, g, b, a)
    local pp = PP()
    if pp.GetBorders and pp.GetBorders(frame) then
        pp.SetBorderColor(frame, r, g, b, a)
    else
        pp.CreateBorder(frame, r, g, b, a, 1, "OVERLAY", 7)
    end
end
Kit.Border = Border

function Kit.Panel(frame, alpha)
    local bg = frame._kitBg
    if not bg then
        bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        bg:SetAllPoints()
        frame._kitBg = bg
    end
    bg:SetColorTexture(BG[1], BG[2], BG[3], alpha or 0.95)
    Border(frame, 0, 0, 0, 1)
    return frame
end

function Kit.Glyph(parent, text, onClick, tip, key)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(18, 18)
    b.t = b:CreateFontString(nil, "OVERLAY")
    Kit.Font(b.t, 14, key)
    b.t:SetPoint("CENTER")
    b.t:SetText(text)
    b.t:SetTextColor(IDLE[1], IDLE[2], IDLE[3])
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        self.t:SetTextColor(Kit.Accent())
        if tip then CludesUI.ShowWidgetTooltip(self, tip) end
    end)
    b:SetScript("OnLeave", function(self)
        self.t:SetTextColor(IDLE[1], IDLE[2], IDLE[3])
        if tip then CludesUI.HideWidgetTooltip() end
    end)
    return b
end

--- A movable window. opts: key (font), strata, special (false: Escape does
--- not close it), onClose. Fields: title, close, header (the line under the
--- title bar).
function Kit.Window(name, w, h, title, opts)
    opts = opts or {}
    local win = CreateFrame("Frame", name, UIParent)
    win:SetSize(w, h)
    win:SetPoint("CENTER", 0, 30)
    win:SetFrameStrata(opts.strata or "HIGH")
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    Kit.Panel(win)
    win.title = win:CreateFontString(nil, "OVERLAY")
    Kit.Font(win.title, 15, opts.key)
    win.title:SetPoint("TOPLEFT", 10, -8)
    win.title:SetText(title or "")
    win.header = win:CreateTexture(nil, "ARTWORK")
    win.header:SetHeight(1)
    win.header:SetPoint("TOPLEFT", 1, -28)
    win.header:SetPoint("TOPRIGHT", -1, -28)
    win.close = Kit.Glyph(win, "x", function()
        if opts.onClose then opts.onClose() end
        win:Hide()
    end, nil, opts.key)
    win.close:SetPoint("TOPRIGHT", -5, -5)
    local function Paint()
        local r, g, b = Kit.Accent()
        win.title:SetTextColor(r, g, b)
        win.header:SetColorTexture(r, g, b, 0.35)
    end
    Paint()
    win:HookScript("OnShow", Paint)
    if name and opts.special ~= false then tinsert(UISpecialFrames, name) end
    return win
end

--- A flat square button. opts: key (font), size (text size), tip. Methods:
--- SetText, GetText, GetTextWidth, SetActive(bool) (the picked tab).
function Kit.Button(parent, text, w, h, onClick, opts)
    opts = opts or {}
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w or 90, h or 22)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(CONTROL_BG[1], CONTROL_BG[2], CONTROL_BG[3], CONTROL_BG[4])
    b._bg = bg
    b.label = b:CreateFontString(nil, "OVERLAY")
    Kit.Font(b.label, opts.size or 12, opts.key)
    b.label:SetPoint("CENTER")
    b.label:SetText(text or "")
    local function Paint(hovered)
        local r, g, bl = Kit.Accent()
        local lit = hovered or b._active
        Border(b, r, g, bl, lit and 1 or 0.45)
        if b._active then
            b.label:SetTextColor(r, g, bl)
            bg:SetColorTexture(r, g, bl, 0.15)
        else
            b.label:SetTextColor(hovered and 1 or IDLE[1], hovered and 1 or IDLE[2], hovered and 1 or IDLE[3])
            bg:SetColorTexture(CONTROL_BG[1], CONTROL_BG[2], CONTROL_BG[3], CONTROL_BG[4])
        end
    end
    b._paint = Paint
    Paint(false)
    b:HookScript("OnEnter", function(self)
        Paint(true)
        if opts.tip then CludesUI.ShowWidgetTooltip(self, opts.tip) end
    end)
    b:HookScript("OnLeave", function()
        Paint(false)
        if opts.tip then CludesUI.HideWidgetTooltip() end
    end)
    if onClick then b:SetScript("OnClick", onClick) end
    function b:SetText(t) self.label:SetText(t) end
    function b:GetText() return self.label:GetText() end
    function b:GetTextWidth() return self.label:GetStringWidth() end
    function b:SetActive(on) self._active = on and true or nil; Paint(self:IsMouseOver()) end
    b:HookScript("OnShow", function(self) Paint(self:IsMouseOver()) end)
    return b
end

--- A square checkbox with its label. Methods: SetChecked, GetChecked,
--- SetLabel. onClick(self) runs after the box flips.
function Kit.Check(parent, label, onClick, key)
    local c = CreateFrame("Button", nil, parent)
    c:SetSize(16, 16)
    local bg = c:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(CONTROL_BG[1], CONTROL_BG[2], CONTROL_BG[3], CONTROL_BG[4])
    c.mark = c:CreateTexture(nil, "ARTWORK")
    c.mark:SetPoint("TOPLEFT", 3, -3)
    c.mark:SetPoint("BOTTOMRIGHT", -3, 3)
    c.text = c:CreateFontString(nil, "OVERLAY")
    Kit.Font(c.text, 12, key)
    c.text:SetPoint("LEFT", c, "RIGHT", 6, 0)
    c.text:SetText(label or "")
    c.text:SetTextColor(IDLE[1], IDLE[2], IDLE[3])
    local function Paint()
        local r, g, b = Kit.Accent()
        Border(c, r, g, b, c:IsMouseOver() and 1 or 0.6)
        c.mark:SetColorTexture(r, g, b, 1)
        c.mark:SetShown(c._checked == true)
    end
    function c:SetChecked(on) self._checked = on and true or false; Paint() end
    function c:GetChecked() return self._checked == true end
    function c:SetLabel(t) self.text:SetText(t) end
    -- The flip is on PreClick, so a caller's own OnClick (SetScript) keeps it.
    c:SetScript("PreClick", function(self) self:SetChecked(not self._checked) end)
    if onClick then c:SetScript("OnClick", onClick) end
    c:SetScript("OnEnter", Paint)
    c:SetScript("OnLeave", Paint)
    c:SetChecked(false)
    return c
end

--- A flat edit box with a grey placeholder while empty and unfocused.
function Kit.Input(parent, w, h, placeholder, key)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(w or 160, h or 22)
    e:SetAutoFocus(false)
    e:SetTextInsets(6, 6, 0, 0)
    local bg = e:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(CONTROL_BG[1], CONTROL_BG[2], CONTROL_BG[3], CONTROL_BG[4])
    Kit.Font(e, 12, key)
    e:SetTextColor(1, 1, 1)
    e.hint = e:CreateFontString(nil, "OVERLAY")
    Kit.Font(e.hint, 12, key)
    e.hint:SetPoint("LEFT", 6, 0)
    e.hint:SetTextColor(0.5, 0.5, 0.5)
    e.hint:SetText(placeholder or "")
    local function Paint()
        local r, g, b = Kit.Accent()
        Border(e, r, g, b, e:HasFocus() and 1 or 0.45)
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
function Kit.Scroll(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    local track = CreateFrame("Frame", nil, parent)
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
        local h = scroll:GetHeight() or 0
        if range <= 0.5 or h <= 0 then
            track:Hide()
            if scroll:GetVerticalScroll() ~= 0 then scroll:SetVerticalScroll(0) end
            return
        end
        track:Show()
        local r, g, b = Kit.Accent()
        thumbTex:SetColorTexture(r, g, b, 0.7)
        local th = math.max(20, h * h / (h + range))
        thumb:SetHeight(th)
        local pos = (scroll:GetVerticalScroll() / range) * (h - th)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -pos)
    end

    local function ScrollTo(v)
        local range = scroll:GetVerticalScrollRange() or 0
        scroll:SetVerticalScroll(math.max(0, math.min(range, v)))
        Update()
    end

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta) ScrollTo(self:GetVerticalScroll() - delta * 40) end)
    scroll:SetScript("OnScrollRangeChanged", Update)
    scroll:SetScript("OnVerticalScroll", Update)
    scroll:SetScript("OnSizeChanged", function(self, w)
        content:SetWidth(w)
        Update()
    end)
    thumb:SetScript("OnMouseDown", function(self)
        local _, cy = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        self._startY, self._startV = cy / scale, scroll:GetVerticalScroll()
        self:SetScript("OnUpdate", function(s)
            local _, y = GetCursorPosition()
            y = y / scale
            local range = scroll:GetVerticalScrollRange() or 0
            local h = scroll:GetHeight() - s:GetHeight()
            if h > 0 then ScrollTo(s._startV + (s._startY - y) / h * range) end
        end)
    end)
    thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
    scroll.Refresh = Update
    track:Hide()
    return scroll, content
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

local function NewNode() return setmetatable({ items = {} }, Node) end

function Node:CreateTitle(text)
    table.insert(self.items, { text = text, noLoc = true, isDisabled = function() return true end })
end
function Node:CreateDivider()
    if #self.items > 0 then table.insert(self.items, "---") end
end
function Node:CreateButton(text, fn)
    local child = NewNode()
    local item = { text = text, noLoc = true, onClick = fn }
    item._node = child
    table.insert(self.items, item)
    return child
end
function Node:CreateRadio(text, isOn, fn)
    table.insert(self.items, { text = text, noLoc = true, isActive = isOn and isOn() or false, onClick = fn })
end
Node.CreateCheckbox = Node.CreateRadio

local function Items(node)
    local out = {}
    for _, item in ipairs(node.items) do
        if type(item) == "table" and item._node then
            local kids = Items(item._node)
            local copy = { text = item.text, noLoc = true, onClick = item.onClick }
            if #kids > 0 then copy.children, copy.onClick = kids, nil end
            out[#out + 1] = copy
        else
            out[#out + 1] = item
        end
    end
    if out[#out] == "---" then out[#out] = nil end
    return out
end

function Kit.ContextMenu(owner, builder, opts)
    local root = NewNode()
    builder(owner, root)
    CludesUI.ShowContextMenu(owner, Items(root), opts)
end
