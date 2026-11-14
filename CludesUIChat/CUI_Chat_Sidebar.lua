if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Chat_Sidebar.lua
--
--  Sidebar side, icon colour, background and scale, free-moved icons, the
--  portal flyout, the input position and the sidebar width.
--  Reads the earlier Chat files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
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

local CFD, GetEditBoxHeight, GetFont = Inner.CFD, Inner.GetEditBoxHeight, Inner.GetFont
local HideSidebarIconTooltip = Inner.HideSidebarIconTooltip
local ShowSidebarIconTooltip = Inner.ShowSidebarIconTooltip

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._internals, which hands the value to every copy.
local BG_R = Inner.BG_R
Inner.bgRSetters[#Inner.bgRSetters + 1] = function(val)
    BG_R = val
end
local BG_G = Inner.BG_G
Inner.bgGSetters[#Inner.bgGSetters + 1] = function(val)
    BG_G = val
end
local BG_B = Inner.BG_B
Inner.bgBSetters[#Inner.bgBSetters + 1] = function(val)
    BG_B = val
end

-- Flip sidebar to left or right side of chat bg
function CHAT.ApplySidebarPosition()
    local conf = CHAT.DB()
    local cf1 = _G.ChatFrame1
    local scrollBar = cf1 and CFD(cf1).sidebar
    if not scrollBar or not CFD(cf1).bg then
        return
    end
    local Pix = CludesUI and CludesUI.PP
    local onePx = (Pix and Pix.mult) or 1
    -- Separate Sidebar: detach from the panel by the configured gap; it keeps
    -- its own bg and gets its own panel-style border (ApplyExtendedBackground).
    local gap = (conf.sidebarSeparate == true) and (conf.sidebarSeparateSpacing or 8) or 0
    scrollBar:ClearAllPoints()
    if CHAT.SB_KIT then
        -- Stock styles: the stock chat button column's own seat.
        CHAT.SB_Place(scrollBar, CFD(cf1).bg, conf)
    elseif conf.sidebarRight then
        scrollBar:SetPoint("TOPLEFT", CFD(cf1).bg, "TOPRIGHT", gap, 0)
        scrollBar:SetPoint("BOTTOMLEFT", CFD(cf1).bg, "BOTTOMRIGHT", gap, 0)
    else
        scrollBar:SetPoint("TOPRIGHT", CFD(cf1).bg, "TOPLEFT", -gap, 0)
        scrollBar:SetPoint("BOTTOMRIGHT", CFD(cf1).bg, "BOTTOMLEFT", -gap, 0)
    end
    -- Divider to the correct edge; hidden in separate mode (it is the joint
    -- line between sidebar and panel).
    if CFD(cf1).sidebarDiv then
        CFD(cf1).sidebarDiv:ClearAllPoints()
        if conf.sidebarRight then
            CFD(cf1).sidebarDiv:SetPoint("TOPLEFT", scrollBar, "TOPLEFT", 0, 0)
            CFD(cf1).sidebarDiv:SetPoint("BOTTOMLEFT", scrollBar, "BOTTOMLEFT", 0, 0)
        else
            CFD(cf1).sidebarDiv:SetPoint("TOPRIGHT", scrollBar, "TOPRIGHT", 0, 0)
            CFD(cf1).sidebarDiv:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMRIGHT", 0, 0)
        end
        -- Hidden borders (the Hide Borders option, and always under the stock
        -- styles) take the divider too, whatever order the passes run in.
        CFD(cf1).sidebarDiv:SetShown(conf.sidebarSeparate ~= true and not CHAT.BordersHidden(conf))
    end

    -- Re-place the behind-tabs divider continuation onto the new edge.
    if CHAT.ApplyTabPadding then
        CHAT.ApplyTabPadding()
    elseif CHAT.ApplyExtendedBackground then
        CHAT.ApplyExtendedBackground()
    end
end

-- Apply icon color to all sidebar icons
function CHAT.ApplyIconColor()
    local conf = CHAT.DB()
    local cf1 = _G.ChatFrame1
    local scrollBar = cf1 and CFD(cf1).sidebar
    if not scrollBar then
        return
    end
    -- Stock kits keep their own art and states; the tooltips ride the hooks
    -- the buttons got at creation.
    if CHAT.SB_KIT then
        return
    end
    local r, g, b
    if conf.iconUseAccent and CludesUI.GetAccentColor then
        r, g, b = CludesUI.GetAccentColor()
    else
        r, g, b = conf.iconR or 1, conf.iconG or 1, conf.iconB or 1
    end
    local ICON_ALPHA = 0.4
    local ICON_HOVER_ALPHA = 0.9
    local d = CFD(cf1)
    local ICON_LABELS = {
        friendsBtn = "Friends",
        guildBtn = "Guild",
        durabilityBtn = "Durability",
        copyBtn = "Copy Chat",
        portalBtn = "M+ Portals",
        voiceBtn = "Voice/Channels",
        chatMenuBtn = "Chat Menu",
        settingsBtn = "Settings",
        scrollBtn = "Scroll to Bottom",
    }
    local fc = d.friendsCount
    local gc = d.guildCount
    local dp = d.durabilityPct
    for _, key in ipairs({
        "friendsBtn",
        "guildBtn",
        "durabilityBtn",
        "copyBtn",
        "portalBtn",
        "voiceBtn",
        "chatMenuBtn",
        "settingsBtn",
        "scrollBtn",
    }) do
        local btn = CFD(cf1)[key]
        if btn and btn._icon then
            btn._icon:SetVertexColor(r, g, b, ICON_ALPHA)
            local labelText = ICON_LABELS[key]
            if key == "friendsBtn" and fc then
                fc:SetTextColor(r, g, b, 0.5)
                btn:SetScript("OnEnter", function(self)
                    btn._icon:SetVertexColor(r, g, b, ICON_HOVER_ALPHA)
                    fc:SetTextColor(r, g, b, 0.9)
                    if not self._freeMoveJustDragged then
                        ShowSidebarIconTooltip(self, labelText)
                    end
                end)
                btn:SetScript("OnLeave", function(self)
                    btn._icon:SetVertexColor(r, g, b, ICON_ALPHA)
                    fc:SetTextColor(r, g, b, 0.5)
                    HideSidebarIconTooltip(self)
                end)
            elseif key == "guildBtn" and gc then
                gc:SetTextColor(r, g, b, 0.5)
                btn:SetScript("OnEnter", function(self)
                    btn._icon:SetVertexColor(r, g, b, ICON_HOVER_ALPHA)
                    gc:SetTextColor(r, g, b, 0.9)
                    if not self._freeMoveJustDragged then
                        ShowSidebarIconTooltip(self, labelText)
                    end
                end)
                btn:SetScript("OnLeave", function(self)
                    btn._icon:SetVertexColor(r, g, b, ICON_ALPHA)
                    gc:SetTextColor(r, g, b, 0.5)
                    HideSidebarIconTooltip(self)
                end)
            elseif key == "durabilityBtn" and dp then
                dp:SetTextColor(r, g, b, 0.5)
                btn:SetScript("OnEnter", function(self)
                    btn._icon:SetVertexColor(r, g, b, ICON_HOVER_ALPHA)
                    dp:SetTextColor(r, g, b, 0.9)
                    if not self._freeMoveJustDragged then
                        ShowSidebarIconTooltip(self, labelText)
                    end
                end)
                btn:SetScript("OnLeave", function(self)
                    btn._icon:SetVertexColor(r, g, b, ICON_ALPHA)
                    dp:SetTextColor(r, g, b, 0.5)
                    HideSidebarIconTooltip(self)
                end)
            else
                btn:SetScript("OnEnter", function(self)
                    btn._icon:SetVertexColor(r, g, b, ICON_HOVER_ALPHA)
                    if not self._freeMoveJustDragged then
                        ShowSidebarIconTooltip(self, labelText)
                    end
                end)
                btn:SetScript("OnLeave", function(self)
                    btn._icon:SetVertexColor(r, g, b, ICON_ALPHA)
                    HideSidebarIconTooltip(self)
                end)
            end
        end
    end
end

-- Hide/show the sidebar background texture
function CHAT.ApplySidebarBackground()
    local conf = CHAT.DB()
    local cf1 = _G.ChatFrame1
    local scrollBar = cf1 and CFD(cf1).sidebar
    if not scrollBar then
        return
    end
    -- Stock styles: no sidebar backdrop (icons over Blizzard's own art).
    local show = not conf.hideSidebarBg and not mod.ChatStock()
    local sbBg = scrollBar:GetRegions()
    if sbBg and sbBg.SetShown then
        sbBg:SetShown(show)
    end
    if Pix.GetBorders(scrollBar) then
        Pix.GetBorders(scrollBar):SetShown(show)
    end
    -- Blizzard Style: the stock column backdrop follows Hide Sidebar Background.
    local bd = CFD(cf1).sbBackdrop
    if bd then
        bd:SetShown(not conf.hideSidebarBg)
        if not conf.hideSidebarBg and CHAT.SB_SyncBackdrop then
            CHAT.SB_SyncBackdrop(true)
        end
    end
    -- Hide the sidebar extension too when the sidebar background is hidden.
    if CHAT.ApplyExtendedBackground then
        CHAT.ApplyExtendedBackground()
    end
end

-- Scale sidebar icon buttons and friends count text
function CHAT.ApplySidebarIconScale()
    local conf = CHAT.DB()
    local scale = conf.sidebarIconScale or 1.0
    local cf1 = _G.ChatFrame1
    local scrollBar = cf1 and CFD(cf1).sidebar
    if not scrollBar then
        return
    end
    -- Stock kits size from their own art (a memo no-op at login and refresh).
    if CHAT.SB_KIT then
        CHAT.SB_ApplyScale(CFD(cf1), scale)
        return
    end

    local BASE_FRIEND = 26
    local BASE_ICON = 22
    local BASE_FONT = 9

    -- _freeMoveH mirrors each icon's height from these constants so
    -- TopYFromSidebarTop never calls GetHeight() -- a geometry resolve that
    -- can taint the Edit-Mode ChatFrame1. Our own frames, so writing is safe.
    for _, key in ipairs({
        "durabilityBtn",
        "copyBtn",
        "portalBtn",
        "voiceBtn",
        "chatMenuBtn",
        "settingsBtn",
        "scrollBtn",
    }) do
        local btn = CFD(cf1)[key]
        if btn then
            btn:SetSize(BASE_ICON * scale, BASE_ICON * scale)
            btn._freeMoveH = BASE_ICON * scale
        end
    end
    if CFD(cf1).friendsBtn then
        CFD(cf1).friendsBtn:SetSize(BASE_FRIEND * scale, BASE_FRIEND * scale)
        CFD(cf1).friendsBtn._freeMoveH = BASE_FRIEND * scale
    end
    if CFD(cf1).friendsCount then
        CFD(cf1).friendsCount:SetFont(GetFont(), upper(7, BASE_FONT * scale), "")
        CFD(cf1).friendsCount._freeMoveH = upper(7, BASE_FONT * scale)
    end

    if CFD(cf1).guildBtn then
        CFD(cf1).guildBtn:SetSize(BASE_FRIEND * scale, BASE_FRIEND * scale)
        CFD(cf1).guildBtn._freeMoveH = BASE_FRIEND * scale
    end
    if CFD(cf1).guildCount then
        CFD(cf1).guildCount:SetFont(GetFont(), upper(7, BASE_FONT * scale), "")
        CFD(cf1).guildCount._freeMoveH = upper(7, BASE_FONT * scale)
    end

    if CFD(cf1).durabilityPct then
        CFD(cf1).durabilityPct:SetFont(GetFont(), upper(7, BASE_FONT * scale), "")
        CFD(cf1).durabilityPct._freeMoveH = upper(7, BASE_FONT * scale)
    end
end

-- Free move: shift+drag sidebar icons to custom positions
local _freeMoveIconHooked = {}

local function GetIconOffset(key)
    local conf = CHAT.DB()
    if not conf.freeMoveIcons or not conf.iconPositions then
        return 0, 0
    end
    local place = conf.iconPositions[key]
    if not place then
        return 0, 0
    end
    return place.x or 0, place.y or 0
end

local function SaveIconOffset(key, posX, posY)
    local conf = CHAT.DB()
    if not conf.iconPositions then
        conf.iconPositions = {}
    end
    conf.iconPositions[key] = { x = posX, y = posY }
end

-- Y offset of `frame`'s TOP edge below the SIDEBAR's TOP edge, from GetPoint (stored
-- anchor data, no resolve) plus each frame's STORED height (_freeMoveH, from
-- ApplySidebarIconScale's size constants). CRITICAL: NEVER call
-- GetHeight/GetWidth/GetCenter or any other geometry- RESOLVING getter here -- they
-- walk the anchor chain icon -> sidebar -> chat bg -> ChatFrame1, and ChatFrame1 is
-- Edit-Mode-secured, so resolving its layout from insecure code TAINTS it (intermittent
-- HistoryKeeper/FCFManager whisper errors, only when geometry was still unresolved at
-- walk time, e.g. login timing). The pre-stored _freeMoveH avoids the resolve entirely.
local function TopYFromSidebarTop(widget, scrollBar, depth)
    if widget == scrollBar or (depth or 0) > 12 then
        return 0
    end
    local anchorPoint, relTo, relPoint, _, dy = widget:GetPoint(1)
    if not anchorPoint or not relTo then
        return 0
    end
    local relTopY = TopYFromSidebarTop(relTo, scrollBar, (depth or 0) + 1)
    local relH = (relTo ~= scrollBar) and (relTo._freeMoveH or 0) or 0
    local relEdgeY = relTopY
    if relPoint and relPoint:find("BOTTOM") then
        relEdgeY = relTopY - relH
    elseif relPoint == "CENTER" or relPoint == "LEFT" or relPoint == "RIGHT" then
        relEdgeY = relTopY - relH / 2
    end
    local edgeY = relEdgeY + (dy or 0)
    if anchorPoint:find("TOP") then
        return edgeY
    end
    if anchorPoint:find("BOTTOM") then
        return edgeY + (widget._freeMoveH or 0)
    end
    return edgeY + (widget._freeMoveH or 0) / 2
end

-- Capture each icon's natural sidebar-EDGE offset (TOP/BOTTOM) once, so
-- re-applies never read live geometry and offsets never compound.
local function CaptureNatural(btn, scrollBar)
    -- Stock sidebar kits: a hidden icon was never laid out by the kit's
    -- chain (a hidden sidebar skips re-anchoring), so its anchors are still
    -- the build-time ones; the pass that first shows it captures from the
    -- real layout. The CludesUI look captures as it always has (saved
    -- offsets are relative to that baseline).
    if btn._freeMoveNat or (CHAT.SB_KIT and not btn:IsShown()) then
        return
    end
    local anchorPoint = btn:GetPoint(1)
    if not anchorPoint then
        return
    end
    if anchorPoint:find("BOTTOM") then
        local _, _, _, _, dy = btn:GetPoint(1)
        btn._freeMoveNat = { edge = "BOTTOM", y = dy or 0 }
    else
        btn._freeMoveNat = { edge = "TOP", y = TopYFromSidebarTop(btn, scrollBar, 0) }
    end
end

-- Re-anchor an icon DIRECTLY to its sidebar edge at natural + saved offset, so
-- each icon moves independently (no chain, no compounding).
local function ApplyIconOffset(btn, scrollBar)
    if not btn or not scrollBar or not btn:IsShown() then
        return
    end
    local nat = btn._freeMoveNat
    if not nat then
        return
    end
    local ox, oy = GetIconOffset(btn._freeMoveKey)
    btn:ClearAllPoints()
    btn:SetPoint(nat.edge, scrollBar, nat.edge, ox, nat.y + oy)
end

local function EnableIconFreeMove(btn)
    if not btn or _freeMoveIconHooked[btn] then
        return
    end
    _freeMoveIconHooked[btn] = true

    local key = btn._freeMoveKey
    if not key then
        return
    end

    btn:SetMovable(true)
    btn:SetClampedToScreen(true)

    local origClick = btn:GetScript("OnClick")
    if origClick then
        btn:SetScript("OnClick", function(self, ...)
            if self._freeMoveJustDragged then
                return
            end
            origClick(self, ...)
        end)
    end

    local startX, startY, baseOX, baseOY

    -- Drag re-anchors to the icon's own sidebar edge at natural + (offset+delta).
    -- GetEffectiveScale walks the PARENT chain (button->sidebar->UIParent), not
    -- the anchor chain to ChatFrame1, so it is taint-safe; GetParent() == sidebar.
    local function FreeMoveOnUpdate(self)
        if not IsMouseButtonDown("LeftButton") then
            self:SetScript("OnUpdate", nil)
            C_Timer.After(0, function()
                self._freeMoveJustDragged = nil
            end)
            return
        end
        local nat = self._freeMoveNat
        if not nat then
            return
        end
        local es = self:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        local nx = baseOX + (cx / es - startX)
        local ny = baseOY + (cy / es - startY)
        self:ClearAllPoints()
        self:SetPoint(nat.edge, self:GetParent(), nat.edge, nx, nat.y + ny)
        SaveIconOffset(key, nx, ny)
    end

    btn:HookScript("OnMouseDown", function(self, btnFrame)
        if btnFrame ~= "LeftButton" or not IsShiftKeyDown() then
            return
        end
        local conf = CHAT.DB()
        if not conf.freeMoveIcons or not self._freeMoveNat then
            return
        end
        self._freeMoveJustDragged = true
        local es = self:GetEffectiveScale()
        startX, startY = GetCursorPosition()
        startX, startY = startX / es, startY / es
        baseOX, baseOY = GetIconOffset(key)
        self:SetScript("OnUpdate", FreeMoveOnUpdate)
    end)

    btn:HookScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        C_Timer.After(0, function()
            self._freeMoveJustDragged = nil
        end)
    end)
end

function CHAT.ApplyIconFreeMove()
    local conf = CHAT.DB()
    local cf1 = _G.ChatFrame1
    local scrollBar = cf1 and CFD(cf1).sidebar
    if not scrollBar then
        return
    end

    -- Free move is opt-in: OFF does NOTHING here -- no anchor-chain capture, no
    -- drag-hook install, no offsets. This gate is required: CaptureNatural walks the
    -- icon anchor chain, and for users whose chat geometry is still unresolved at
    -- login, that walk resolves up through and TAINTS the Edit-Mode ChatFrame1. Turning
    -- the toggle on re-runs ApplySidebarIcons -> ApplyIconFreeMove, installing hooks
    -- immediately; untouched icons keep their natural chain layout.
    if not conf.freeMoveIcons then
        return
    end

    local btns = {
        { ref = "friendsBtn", key = "friends" },
        { ref = "guildBtn", key = "guild" },
        { ref = "durabilityBtn", key = "durability" },
        { ref = "copyBtn", key = "copy" },
        { ref = "portalBtn", key = "portals" },
        { ref = "voiceBtn", key = "voice" },
        { ref = "chatMenuBtn", key = "chatmenu" },
        { ref = "settingsBtn", key = "settings" },
        { ref = "scrollBtn", key = "scroll" },
    }

    -- PHASE 1 -- capture every icon's natural anchor (GetPoint data + stored heights,
    -- never a geometry-resolving getter; see TopYFromSidebarTop) and install drag
    -- hooks. MUST complete for ALL icons before Phase 2's re-anchoring: interleaving
    -- would let a later icon's chain-walk read an earlier icon's already-applied offset
    -- and bake it into its "natural" position -- drift on every reload.
    for _, details in ipairs(btns) do
        local btn = CFD(cf1)[details.ref]
        -- The chat-anchored scroll button is outside the sidebar chain; free
        -- move must not capture or re-anchor it.
        if details.ref == "scrollBtn" and conf.scrollButtonOnChat then
            btn = nil
        end
        if btn then
            btn._freeMoveKey = details.key
            CaptureNatural(btn, scrollBar)
            EnableIconFreeMove(btn)
        end
    end

    -- PHASE 2 -- re-anchor each icon to its sidebar edge at natural + saved
    -- offset, so icons move independently.
    for _, details in ipairs(btns) do
        local btn = CFD(cf1)[details.ref]
        if details.ref == "scrollBtn" and conf.scrollButtonOnChat then
            btn = nil
        end
        if btn then
            ApplyIconOffset(btn, scrollBar)
        end
    end
end

-- Portal flyout: CludesUI.CreatePortalFlyout, built on first open.
local _portalFlyout

function CHAT.TogglePortalFlyout(anchorBtn)
    if InCombatLockdown() then
        return
    end
    if not _portalFlyout then
        _portalFlyout = CUI.CreatePortalFlyout({
            -- unitEvents: the cast events it watches only ever matter for the player.
            name = "CUIChat",
            bg = { BG_R, BG_G, BG_B },
            labelFont = GetFont(),
            unitEvents = true,
            labelFlags = (CUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG",
        })
    end
    local flyout = _portalFlyout
    -- Visibility, not the shown flag: leaving the house editor hides our host
    -- out from under a flyout that is still flagged shown, and a stale flag
    -- would eat the next click.
    if flyout:IsVisible() then
        flyout:Hide()
    else
        -- Absolute screen position: a protected frame cannot anchor to a
        -- non-secure region.
        local bs = anchorBtn:GetEffectiveScale()
        local fontStr = flyout:GetEffectiveScale()
        local bTop = anchorBtn:GetTop() * bs
        local conf = CHAT.DB()
        flyout:ClearAllPoints()
        if conf.sidebarRight then
            local bLeft = anchorBtn:GetLeft() * bs
            flyout:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", (bLeft - 4) / fontStr, (bTop + 4) / fontStr)
        else
            local bRight = anchorBtn:GetRight() * bs
            flyout:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (bRight + 4) / fontStr, (bTop + 4) / fontStr)
        end
        CHAT.HostPopup(flyout)
        flyout._toggle = anchorBtn
        flyout:Show()
    end
end

-- How far below the chat frame's top edge the overlaid input sits. Keeps the
-- box's vertically-centered text off the tab band at small editBoxHeight
-- values (the box grows downward from a fixed top anchor, so shrinking it
-- otherwise walks the text up toward a flush top edge). THREE places consume
-- it and must agree or the parts separate: the edit box anchor, the reserved
-- strip height, and the divider that marks the box's lower edge.
local INPUT_TOP_DROP = 5

-- Input-on-top overlays the top strip of the text area, and OUR message frame
-- hands that strip back (_smfTopExtra) so no line renders under the input.
-- Reserving it permanently costs a line of chat even while nothing is being
-- typed -- the strip sits empty and the topmost message is clipped -- so the
-- reservation follows the edit box's SHOWN state on the permanent frames 1-10,
-- whose edit boxes may be script-hooked. Temp windows (11+) must never be
-- hooked (see SkinEditBox's taint note) and keep the static reservation.
-- The box overlaying a window is NOT always that window's own. Blizzard's
-- DEFAULT chatStyle ("classic") routes every window's input through
-- DEFAULT_CHAT_FRAME's box -- ChatFrameUtil.ChooseBoxForSend returns
-- DEFAULT_CHAT_FRAME.editBox outright in that mode, before it ever looks at
-- the preferred frame -- so on any tab but the first, ChatFrame1EditBox is
-- what appears over the text while that tab's OWN edit box stays hidden.
-- Keying the strip off cf's own box therefore leaves every other tab unmasked
-- and reserves a strip on ChatFrame1's hidden window instead. Docked windows
-- share one rect, so a box shown on any docked frame is drawn over whichever
-- docked frame is currently visible.
--
-- A box is UP while chat is using it. Classic Style shows a box only then, so
-- shown is enough. IM Style (Blizzard's default) keeps an idle box shown,
-- emptied and faded to 35% (invisible under our skin, so its strip read as
-- dead space): there a box is up while it has the focus, or while chat still
-- treats it as the active box and Blizzard's own rule keeps it open without
-- the focus (a draft left in it). That also reads right inside the focus-lost
-- callback: clicking away from an emptied box fires it before Blizzard
-- deactivates the box, and the rule already says it closes.
local function BoxUp(box)
    if not box:IsShown() then
        return false
    end
    if GetCVar("chatStyle") ~= "im" then
        return true
    end
    if box:HasFocus() then
        return true
    end
    return box == ChatFrameUtil.GetActiveWindow() and not box:ShouldDeactivateChatOnEditFocusLost()
end

local function DockedEditBoxShown()
    for i = 1, 10 do
        local ownerFrame = _G["ChatFrame" .. i]
        local box = ownerFrame and _G["ChatFrame" .. i .. "EditBox"]
        if box and ownerFrame.isDocked and BoxUp(box) then
            return true
        end
    end
    return false
end

function CHAT.InputTopStripActive(castFrame)
    if not CHAT.InputOnTop(CHAT.DB()) then
        return false
    end
    local name = castFrame:GetName()
    local eb = name and _G[name .. "EditBox"]
    if not eb then
        return false
    end
    local position = tonumber(name:match("ChatFrame(%d+)"))
    if not (position and position <= 10) then
        return true
    end
    -- Own box up ("im" style, and any undocked window).
    if BoxUp(eb) then
        return true
    end
    return (castFrame.isDocked and castFrame:IsShown() and DockedEditBoxShown()) and true or false
end

-- Every managed frame, not just one: the box that showed belongs to ChatFrame1
-- while the strip is owed to the selected tab (see InputTopStripActive), so a
-- single-frame re-derive off the edit box hooks updates the wrong window.
function CHAT.RefreshInputTopStrips()
    for i = 1, 20 do
        local castFrame = _G["ChatFrame" .. i]
        if castFrame and CFD(castFrame).bg then
            CHAT.ApplyInputTopStrip(castFrame)
        end
    end
end

-- Re-derive one frame's reserved strip. Only the text area moves: the panel
-- rect stays put (input-on-top never changed _bgIns), so nothing outside our
-- message frame is touched. The divider marks the input's edge and would cut
-- across a message once the strip is released, so it follows the same state.
function CHAT.ApplyInputTopStrip(castFrame)
    local d = CFD(castFrame)
    if not d.bg then
        return
    end
    local conf = CHAT.DB()
    local isActive = CHAT.InputTopStripActive(castFrame)
    -- The strip reaches INPUT_TOP_DROP further than the box is tall, since the
    -- box starts that far down from cf's top edge.
    local wanted = isActive and (GetEditBoxHeight() + 4 + INPUT_TOP_DROP) or nil
    local changed = d._smfTopExtra ~= wanted
    d._smfTopExtra = wanted
    -- The `not cfg.inputOnTop` arm is load-bearing, not redundant: bottom mode
    -- leaves the divider to ApplyBorders, and the toggle-off pass reaches here
    -- without ever calling it -- dropping the arm strands the divider hidden.
    if d.inputDiv then
        d.inputDiv:SetShown(not CHAT.BordersHidden(conf) and (not CHAT.InputOnTop(conf) or isActive))
    end
    -- IM Style: with its strip released, an idle box still lies over the top
    -- lines of the text, invisible, so it lets clicks through (links there stay
    -- clickable) until chat opens it again. Permanent windows only, and only a
    -- box switched off here is switched back on.
    local name = castFrame:GetName()
    local position = name and tonumber(name:match("^ChatFrame(%d+)$"))
    local eb = position and position <= 10 and _G[name .. "EditBox"]
    if eb then
        local idle = CHAT.InputOnTop(conf) and eb:IsShown() and not BoxUp(eb)
        local ed = CFD(eb)
        if idle and not ed.mouseOff and eb:IsMouseEnabled() then
            eb:EnableMouse(false)
            ed.mouseOff = true
        elseif not idle and ed.mouseOff then
            eb:EnableMouse(true)
            ed.mouseOff = nil
        end
    end
    if changed and CHAT.EngineLayoutWindow then
        CHAT.EngineLayoutWindow(castFrame)
    end
end

-- Flip edit box between bottom (default) and top of chat panel
function CHAT.ApplyInputPosition()
    local conf = CHAT.DB()
    local onTop = CHAT.InputOnTop(conf)
    local inputHeight = GetEditBoxHeight()
    -- Stock styles: Blizzard's own input box keeps Blizzard's own height and
    -- anchor shape (SeatStockBackground only moves it sideways with the
    -- background, on the permanent windows), and the panel -- which carries no
    -- paint there, only the sidebar's anchor -- spans the revealed frame art
    -- out to its border (the background re-seated STOCK_BG_X past each side,
    -- +3 above and -6 below, then 4px corners; see SeatStockBackground), so
    -- the sidebar sits flush against Blizzard's border.
    local stock = mod.ChatStock()
    local stockX = CHAT.STOCK_BG_X + 4
    -- WoW Forever: our input box in its own bronze frame under the message
    -- frame (CludesUIChat_Forever.lua records the panel insets).
    local fv = mod.ChatForever()

    for i = 1, 20 do
        local castFrame = _G["ChatFrame" .. i]
        if castFrame and CFD(castFrame).bg then
            local name = castFrame:GetName()
            if not name then
                break
            end
            local eb = _G[name .. "EditBox"]
            local backdrop = CFD(castFrame).bg
            local div = CFD(castFrame).inputDiv

            if fv then
                CHAT.FV_SeatInput(castFrame, eb, inputHeight)
                CHAT.ApplyInputTopStrip(castFrame)
                if CHAT.PositionChatPanel then
                    CHAT.PositionChatPanel(castFrame)
                end
            elseif stock then
                CFD(castFrame)._bgIns = { l = -stockX, r = stockX, t = 7, b = -10 }
                CHAT.ApplyInputTopStrip(castFrame)
                if CHAT.PositionChatPanel then
                    CHAT.PositionChatPanel(castFrame)
                end
            else
                if eb then
                    eb:ClearAllPoints()
                    if onTop then
                        -- Below the tab band, INSIDE the panel: the input
                        -- overlays the top strip of the text area (the space
                        -- above the frame is the tab band's home, and tab
                        -- geometry is Blizzard's -- never moved for us). Our
                        -- message frame hands the strip back via _smfTopExtra;
                        -- line alignment with Blizzard's invisible text is
                        -- unaffected because chat renders bottom-up from a
                        -- shared bottom edge, and the input covers the
                        -- hit-zones of the lines it hides.
                        eb:SetPoint("TOPLEFT", castFrame, "TOPLEFT", -10, -INPUT_TOP_DROP)
                        eb:SetPoint("TOPRIGHT", castFrame, "TOPRIGHT", 5, -INPUT_TOP_DROP)
                        local bgLvl = CFD(castFrame).bg:GetFrameLevel() or 1
                        if eb:GetFrameLevel() < bgLvl + 5 then
                            eb:SetFrameLevel(bgLvl + 5)
                        end
                    else
                        eb:SetPoint("TOPLEFT", castFrame, "BOTTOMLEFT", -10, -8)
                        eb:SetPoint("TOPRIGHT", castFrame, "BOTTOMRIGHT", 5, -8)
                    end
                    eb:SetHeight(inputHeight)
                end

                if div then
                    div:ClearAllPoints()
                    if onTop then
                        -- Flush with the box's LOWER edge, which starts
                        -- INPUT_TOP_DROP down from cf's top and runs inputHeight
                        -- tall -- miss the drop and the line cuts through the box.
                        local divY = -(inputHeight + INPUT_TOP_DROP)
                        div:SetPoint("TOPLEFT", castFrame, "TOPLEFT", -10, divY)
                        div:SetPoint("TOPRIGHT", castFrame, "TOPRIGHT", 10, divY)
                    else
                        div:SetPoint("BOTTOMLEFT", castFrame, "BOTTOMLEFT", -10, -8)
                        div:SetPoint("BOTTOMRIGHT", castFrame, "BOTTOMRIGHT", 10, -8)
                    end
                end

                if backdrop then
                    -- The panel is placed NUMERICALLY, never anchored to cf (see
                    -- PositionChatPanel): record the insets this input layout wants
                    -- and let the positioner apply them against the chat frame's
                    -- rect. Anchoring here would put our frame back into
                    -- Blizzard's rect chain -- the whole bug. Only the vertical
                    -- edge may expand; horizontal geometry stays independent.
                    local d = CFD(castFrame)
                    d._bgIns = {
                        l = -10,
                        r = 10,
                        t = 3,
                        b = onTop and -6 or (eb and -(12 + inputHeight) or -6),
                    }
                    -- Input-on-top: the panel keeps its normal rect; only OUR
                    -- message frame's text area shrinks under the overlaid input,
                    -- and only while that input is actually up (see
                    -- ECHAT.ApplyInputTopStrip). EngineLayoutWindows at the tail
                    -- of this function relayouts every window either way.
                    CHAT.ApplyInputTopStrip(castFrame)
                    if CHAT.PositionChatPanel then
                        CHAT.PositionChatPanel(castFrame)
                    end
                end
            end -- not stock
        end
    end
    -- Our message frames derive their text area from the recorded insets.
    if CHAT.EngineLayoutWindows then
        CHAT.EngineLayoutWindows()
    end
end

function CHAT.ApplySidebarWidth()
    local cf1 = _G.ChatFrame1
    local sidebar = cf1 and CFD(cf1).sidebar
    if not sidebar then
        return
    end
    sidebar:SetWidth(
        min(
            100,
            upper(
                30,
                CHAT.DB().sidebarWidth or (CHAT.SidebarWidthDefault and CHAT.SidebarWidthDefault() or 40)
            )
        )
    )
    if CHAT.ApplySidebarPosition then
        CHAT.ApplySidebarPosition()
    end
end

Inner.broken = false
