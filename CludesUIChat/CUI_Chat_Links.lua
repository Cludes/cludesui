if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Chat_Links.lua
--
--  Reading the chat text, the copy popup, URL detection with its popup and
--  the hyperlink tooltip.
--  Reads the earlier Chat files through ns and ns._internals.
-------------------------------------------------------------------------------
local addonName, mod = ...
local Inner = mod._internals
-- CludesUIChat.lua or an earlier CUI_Chat_*.lua file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local CUI = _G.CludesUI
local CHAT = mod.ECHAT
local Pix = CUI.PP
local min, upper = min, max

local GetFont = Inner.GetFont

-------------------------------------------------------------------------------
--  Chat text helpers
-------------------------------------------------------------------------------
local function StripUIEscapes(textValue)
    if not textValue then
        return ""
    end
    textValue = textValue:gsub("|H.-|h(.-)|h", "%1") -- hyperlinks -> display text
    textValue = textValue:gsub("|T.-|t", "") -- textures
    textValue = textValue:gsub("|A.-|a", "") -- atlas
    textValue = textValue:gsub("|K.-|k", "") -- secret value placeholders
    textValue = textValue:gsub("|n", "\n") -- newlines
    textValue = textValue:gsub("||", "|") -- escaped pipes
    -- Keep |cXXXXXXXX and |r color codes so the copy popup preserves colors
    return textValue
end

-- Read all messages from the active window on demand. The primary source is
-- OUR message frame for the selected window; the hosted combat log (still
-- Blizzard-rendered) and any window the engine has not integrated fall back
-- to the Blizzard buffer read. Secret lines are skipped either way.
local function ReadActiveChatText()
    local selected = GENERAL_CHAT_DOCK
        and FCFDock_GetSelectedWindow
        and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
    local castFrame = selected or ChatFrame1
    if not castFrame then
        return ""
    end
    local raw = {}
    local usedEngine = false
    if
        CHAT.EngineGetMessageLines
        and mod._chatWins
        and mod._chatWins[castFrame]
        and not (mod._clHosted and castFrame == _G.ChatFrame2)
    then
        CHAT.EngineGetMessageLines(castFrame, raw)
        usedEngine = true
    end
    if not usedEngine then
        if not castFrame.GetNumMessages then
            return ""
        end
        local num = castFrame:GetNumMessages()
        for index = 1, num do
            local success, textValue = pcall(castFrame.GetMessageInfo, castFrame, index)
            if success then
                raw[#raw + 1] = textValue
            end
        end
    end
    if #raw == 0 then
        return "(No chat history)"
    end
    local lines = {}
    for index = 1, #raw do
        local textValue = raw[index]
        if textValue and not (issecretvalue and issecretvalue(textValue)) then
            local sok, stripped = pcall(StripUIEscapes, textValue)
            if sok and stripped then
                lines[#lines + 1] = stripped
            end
        end
    end
    return table.concat(lines, "\n")
end

-------------------------------------------------------------------------------
--  Copy popup (used by sidebar copy-chat button)
-------------------------------------------------------------------------------

local copyDimmer

local function ShowCopyPopup(textValue)
    if not copyDimmer then
        local POPUP_W, POPUP_H = 520, 340

        local dimmer = CreateFrame("Frame", nil, UIParent)
        dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
        dimmer:SetAllPoints(UIParent)
        dimmer:EnableMouse(true)
        dimmer:EnableMouseWheel(true)
        dimmer:SetScript("OnMouseWheel", function() end)
        dimmer:Hide()
        local dimTex = CUI.SolidTex(dimmer, "BACKGROUND", 0, 0, 0, 0.25)
        dimTex:SetAllPoints()

        local dialog = CreateFrame("Frame", nil, dimmer)
        dialog:SetSize(POPUP_W, POPUP_H)
        dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetFrameLevel(dimmer:GetFrameLevel() + 10)
        dialog:EnableMouse(true)

        local backdrop = CUI.SolidTex(dialog, "BACKGROUND", 0.062, 0.070, 0.082, 0.95)
        backdrop:SetAllPoints()
        CUI.MakeBorder(dialog, 1, 1, 1, 0.15, CUI.PanelPP)

        -- Blizzard template: scrolling + selection built in
        local textBox = CreateFrame("Frame", nil, dialog, "ScrollingEditBoxTemplate")
        textBox:SetPoint("TOPLEFT", dialog, "TOPLEFT", 20, -20)
        textBox:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -20, 60)

        local editBox = textBox:GetEditBox()
        editBox:SetFont(GetFont(), 12, CUI.GetFontOutlineFlag("chat") or "")
        editBox:SetTextColor(1, 1, 1, 0.75)
        editBox:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            dimmer:Hide()
        end)
        editBox:SetScript("OnChar", function(self)
            if self._readOnlyText then
                self:SetText(self._readOnlyText)
                self:HighlightText()
            end
        end)

        -- Thin interactive scrollbar reading from the template's ScrollBox
        local scrollBox = textBox:GetScrollBox()
        local track = CreateFrame("Button", nil, dialog)
        track:SetWidth(8)
        track:SetPoint("TOPRIGHT", textBox, "TOPRIGHT", 2, -2)
        track:SetPoint("BOTTOMRIGHT", textBox, "BOTTOMRIGHT", 2, 2)
        track:SetFrameLevel(dialog:GetFrameLevel() + 5)
        track:EnableMouse(true)
        track:RegisterForClicks("AnyUp")

        local thumb = track:CreateTexture(nil, "ARTWORK")
        thumb:SetColorTexture(1, 1, 1, 0.27)
        thumb:SetWidth(4)
        thumb:SetHeight(40)
        thumb:SetPoint("TOP", track, "TOP", 0, 0)

        local _sbDragging = false
        local _sbDragOffsetY = 0

        local function UpdateThumb()
            if not scrollBox then
                thumb:Hide()
                return
            end
            local ext = scrollBox:GetVisibleExtentPercentage()
            if not ext or ext >= 1 then
                thumb:Hide()
                return
            end
            thumb:Show()
            local trackH = track:GetHeight()
            local thumbH = upper(20, trackH * ext)
            thumb:SetHeight(thumbH)
            local pct = scrollBox:GetScrollPercentage() or 0
            thumb:ClearAllPoints()
            thumb:SetPoint("TOP", track, "TOP", 0, -(pct * (trackH - thumbH)))
        end

        local function SetScrollFromY(cursorY)
            local trackH = track:GetHeight()
            local ext = scrollBox:GetVisibleExtentPercentage() or 1
            local thumbH = upper(20, trackH * ext)
            local maxTravel = trackH - thumbH
            if maxTravel <= 0 then
                return
            end
            local trackTop = track:GetTop()
            if not trackTop then
                return
            end
            local scale = track:GetEffectiveScale()
            local localY = trackTop - (cursorY / scale) - _sbDragOffsetY
            local pct = upper(0, min(1, localY / maxTravel))
            scrollBox:SetScrollPercentage(pct)
        end

        track:SetScript("OnMouseDown", function(self, btnFrame)
            if btnFrame ~= "LeftButton" then
                return
            end
            local _, cursorY = GetCursorPosition()
            local scale = self:GetEffectiveScale()
            local trackTop = self:GetTop()
            if not trackTop then
                return
            end
            local thumbTop = thumb:GetTop()
            local thumbBot = thumb:GetBottom()
            if thumbTop and thumbBot then
                local localCursor = cursorY / scale
                if localCursor <= thumbTop and localCursor >= thumbBot then
                    _sbDragOffsetY = thumbTop - localCursor
                    _sbDragging = true
                    return
                end
            end
            -- Not on the thumb: jump to the clicked position
            _sbDragOffsetY = (thumb:GetHeight() or 20) / 2
            _sbDragging = true
            SetScrollFromY(cursorY)
        end)
        track:SetScript("OnMouseUp", function()
            _sbDragging = false
        end)

        -- Polls only while the popup is open (hidden frame otherwise)
        local pollFrame = CreateFrame("Frame")
        pollFrame:Hide()
        local _lastPct, _lastExt = -1, -1
        pollFrame:SetScript("OnUpdate", function()
            if _sbDragging then
                local _, cursorY = GetCursorPosition()
                SetScrollFromY(cursorY)
            end
            local ext = scrollBox:GetVisibleExtentPercentage() or 1
            local pct = scrollBox:GetScrollPercentage() or 0
            if ext == _lastExt and pct == _lastPct then
                return
            end
            _lastExt, _lastPct = ext, pct
            UpdateThumb()
        end)
        dimmer:HookScript("OnShow", function()
            _lastPct, _lastExt = -1, -1
            pollFrame:Show()
        end)
        dimmer:HookScript("OnHide", function()
            _sbDragging = false
            pollFrame:Hide()
        end)

        dialog._textBox = textBox
        dialog._editBox = editBox

        local closeBtn = CreateFrame("Button", nil, dialog)
        closeBtn:SetSize(90, 24)
        closeBtn:SetPoint("BOTTOM", dialog, "BOTTOM", 0, 14)
        closeBtn:SetFrameLevel(dialog:GetFrameLevel() + 2)
        CUI.MakeStyledButton(closeBtn, "Close", 10, CUI.RB_COLOURS, function()
            dimmer:Hide()
        end)

        dimmer:SetScript("OnMouseDown", function()
            if not dialog:IsMouseOver() then
                dimmer:Hide()
            end
        end)

        -- SetPropagateKeyboardInput is blocked in combat on every frame (a pcall
        -- does not stop the block): the shared popup keyboard takes the keys out
        -- of combat only, and in combat the popup stands aside (its focused edit
        -- box still closes it on Escape).
        CUI.PopupTakeKeys(dialog, dimmer)
        dialog:SetScript("OnKeyDown", function(self, key)
            if InCombatLockdown() then
                return
            end
            if key == "ESCAPE" then
                self:SetPropagateKeyboardInput(false)
                dimmer:Hide()
            else
                self:SetPropagateKeyboardInput(true)
            end
        end)

        dialog._dimmer = dimmer
        copyDimmer = dimmer
        copyDimmer._popup = dialog
    end

    local dialog = copyDimmer._popup
    dialog._textBox:SetText(textValue)
    dialog._editBox._readOnlyText = textValue
    CHAT.HostPopup(copyDimmer)
    copyDimmer:Show()
    C_Timer.After(0.05, function()
        dialog._editBox:SetFocus()
        -- Open at the newest lines: cursor to the end, then pin the scroll there
        dialog._editBox:SetCursorPosition(#textValue)
        dialog._editBox:HighlightText()
        dialog._textBox:GetScrollBox():ScrollToEnd(true)
    end)
end

-------------------------------------------------------------------------------
--  URL detection + inline copy popup
-------------------------------------------------------------------------------
local URL_PATTERNS = {
    "%f[%S](%a[%w+.-]+://%S+)",
    "^(%a[%w+.-]+://%S+)",
    "%f[%S](www%.[-%w_%%]+%.%a%a+/%S+)",
    "^(www%.[-%w_%%]+%.%a%a+/%S+)",
    "%f[%S](www%.[-%w_%%]+%.%a%a+)",
    "^(www%.[-%w_%%]+%.%a%a+)",
}

-- Literal pre-check so the regex pass is skipped entirely for messages with no
-- URL-like substring (the overwhelming majority).
local function ContainsURL(textValue)
    if not textValue then
        return false
    end
    return textValue:find("://", 1, true) or textValue:find("www.", 1, true)
end

-- Substitution string built once (the color hex is constant)
local _urlSubstitution
local function _GetUrlSubstitution()
    if not _urlSubstitution then
        local eg = CUI.CLUDES_GREEN or { r = 0.05, g = 0.82, b = 0.61 }
        local hex = CludesUI.HexColor(eg.r, eg.g, eg.b)
        _urlSubstitution = hex .. "|H" .. addonName .. "url:%1|h[%1]|h|r"
    end
    return _urlSubstitution
end

local function WrapURLs(textValue)
    if not textValue then
        return textValue
    end
    local sub = _GetUrlSubstitution()
    for _, p in ipairs(URL_PATTERNS) do
        textValue = textValue:gsub(p, sub)
    end
    return textValue
end

local urlBackdrop, urlPopup

local function HideUrlPopup()
    if urlPopup then
        urlPopup:Hide()
    end
    if urlBackdrop then
        urlBackdrop:Hide()
    end
end

local function ShowUrlPopup(url)
    if not urlPopup then
        urlBackdrop = CreateFrame("Button", nil, UIParent)
        urlBackdrop:SetFrameStrata("DIALOG")
        urlBackdrop:SetFrameLevel(499)
        urlBackdrop:SetAllPoints(UIParent)
        local bdTex = urlBackdrop:CreateTexture(nil, "BACKGROUND")
        bdTex:SetAllPoints()
        bdTex:SetColorTexture(0, 0, 0, 0.10)
        local fadeIn = urlBackdrop:CreateAnimationGroup()
        fadeIn:SetToFinalAlpha(true)
        local a = fadeIn:CreateAnimation("Alpha")
        a:SetFromAlpha(0)
        a:SetToAlpha(1)
        a:SetDuration(0.2)
        urlBackdrop._fadeIn = fadeIn
        urlBackdrop:RegisterForClicks("AnyUp")
        urlBackdrop:SetScript("OnClick", HideUrlPopup)
        urlBackdrop:Hide()

        urlPopup = CreateFrame("Frame", nil, UIParent)
        urlPopup:SetFrameStrata("DIALOG")
        urlPopup:SetFrameLevel(500)
        urlPopup:SetSize(340, 52)
        urlPopup:EnableMouse(true)
        local popFade = urlPopup:CreateAnimationGroup()
        popFade:SetToFinalAlpha(true)
        local pa = popFade:CreateAnimation("Alpha")
        pa:SetFromAlpha(0)
        pa:SetToAlpha(1)
        pa:SetDuration(0.2)
        urlPopup._fadeIn = popFade

        local backdrop = urlPopup:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0.062, 0.070, 0.082, 0.97)
        if Pix and Pix.CreateBorder then
            Pix.CreateBorder(urlPopup, 1, 1, 1, 0.15, 1, "OVERLAY", 7)
        end

        local hint = urlPopup:CreateFontString(nil, "OVERLAY")
        hint:SetFont(GetFont(), 8, "")
        hint:SetTextColor(1, 1, 1, 0.5)
        hint:SetPoint("TOP", urlPopup, "TOP", 0, -6)
        hint:SetText(CludesUI.L("Ctrl+C to copy, Escape to close"))

        local eb = CreateFrame("EditBox", nil, urlPopup)
        eb:SetSize(300, 16)
        eb:SetPoint("TOP", hint, "BOTTOM", 0, -4)
        eb:SetFont(GetFont(), 11, "")
        eb:SetAutoFocus(false)
        eb:SetJustifyH("CENTER")
        local ebBg = eb:CreateTexture(nil, "BACKGROUND")
        ebBg:SetColorTexture(0.098, 0.108, 0.120, 1)
        ebBg:SetPoint("TOPLEFT", -6, 4)
        ebBg:SetPoint("BOTTOMRIGHT", 6, -4)
        if Pix and Pix.CreateBorder then
            Pix.CreateBorder(eb, 1, 1, 1, 0.02, 1, "OVERLAY", 7)
        end
        eb:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            HideUrlPopup()
        end)
        eb:SetScript("OnKeyDown", function(self, key)
            if key == "C" and IsControlKeyDown() then
                C_Timer.After(0.05, HideUrlPopup)
            end
        end)
        eb:SetScript("OnMouseUp", function(self)
            self:HighlightText()
        end)
        urlPopup:SetScript("OnMouseDown", function()
            urlPopup._eb:SetFocus()
            urlPopup._eb:HighlightText()
        end)
        urlPopup._eb = eb
    end
    urlPopup._eb:SetText(url)
    urlPopup:ClearAllPoints()
    local cx, cy = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    urlPopup:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", cx / scale, cy / scale + 10)
    CHAT.HostPopup(urlBackdrop)
    CHAT.HostPopup(urlPopup)
    urlBackdrop:SetAlpha(0)
    urlBackdrop:Show()
    urlBackdrop._fadeIn:Play()
    urlPopup:SetAlpha(0)
    urlPopup:Show()
    urlPopup._fadeIn:Play()
    urlPopup._eb:SetFocus()
    urlPopup._eb:HighlightText()
end

-------------------------------------------------------------------------------
--  Hyperlink tooltip on hover + click-to-toggle item detail popup
-------------------------------------------------------------------------------
local TOOLTIP_LINK_TYPES = {
    achievement = true,
    apower = true,
    currency = true,
    enchant = true,
    glyph = true,
    instancelock = true,
    item = true,
    keystone = true,
    quest = true,
    spell = true,
    talent = true,
    unit = true,
}

local _hyperlinkEntered = nil

local function OnHyperlinkEnter(self, hyperlink)
    -- Secret link (lockdown line): match would error; no tooltip either way.
    if _G.issecretvalue and _G.issecretvalue(hyperlink) then
        return
    end
    local conf = CHAT.DB()
    if conf.hideTooltipOnHover then
        return
    end
    local linkType = hyperlink:match("^([^:]+)")
    if TOOLTIP_LINK_TYPES[linkType] then
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(hyperlink)
        GameTooltip:Show()
        _hyperlinkEntered = self
    end
end

local function OnHyperlinkLeave(self)
    if _hyperlinkEntered then
        _hyperlinkEntered = nil
        GameTooltip:Hide()
    end
end

-- Open the copy popup when a wrapped URL link is clicked. Also the mirror
-- for the censored-message links ("[Show Message]" and its send/rewrite
-- siblings): their handlers rewrite or remove the stored line IN PLACE on
-- every chat frame (TransformMessages / RemoveMessagesByPredicate -- no
-- AddMessage, no event), so the engine window would keep showing the
-- placeholder; this post-hook runs after the handler and queues the same
-- deferred rebuild the CAUTIONARY_CHAT_MESSAGE mirror uses.
hooksecurefunc("SetItemRef", function(itemLink)
    if not itemLink then
        return
    end
    if _G.issecretvalue and _G.issecretvalue(itemLink) then
        return
    end
    if itemLink:find("^censoredmessage") then
        if CHAT.EngineQueueRebuildAll then
            CHAT.EngineQueueRebuildAll()
        end
        return
    end
    local url = itemLink:match("^" .. addonName .. "url:(.+)$")
    if url then
        ShowUrlPopup(url)
    end
end)

Inner.ContainsURL, Inner.OnHyperlinkEnter = ContainsURL, OnHyperlinkEnter
Inner.OnHyperlinkLeave, Inner.ReadActiveChatText = OnHyperlinkLeave, ReadActiveChatText
Inner.ShowCopyPopup, Inner.WrapURLs = ShowCopyPopup, WrapURLs
Inner.broken = false
