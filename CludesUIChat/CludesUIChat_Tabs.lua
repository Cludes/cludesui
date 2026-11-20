if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIChat_Tabs.lua
--
--  Ghost tab visuals over Blizzard's REAL tab strip.
--
--  Blizzard's tabs stay fully alive as the interaction plane: every click,
--  drag-reorder, context menu action (rename, font size, new window, close),
--  and the whole temp-whisper lifecycle is a hardware event on a Blizzard
--  frame, so every dock/selection write stays SECURE. This module never
--  selects, closes, creates, renames, or reorders a window from Lua -- an
--  insecure FCFDock_SelectWindow call taints dock.selected/isDirty, and the
--  secure whisper-window creation chain reads those slots (FCF_DockUpdate ->
--  FCFDock_UpdateTabs) and then dies on secret header math in UpdateHeader.
--  Field-measured via taintLog 2; do not reintroduce ANY management call.
--
--  The stock strip is invisible but clickable: GeneralDockManager:SetAlpha(0)
--  -- alpha does not disable mouse input, the slot is written by nothing in
--  Blizzard code (field-proven by the old skin's dock fade), and per-tab
--  alphas (which FCFTab_UpdateAlpha rewrites constantly) multiply against it
--  to zero. ZERO writes of any kind go to the tabs themselves: no texture
--  strips, no text recolors, no anchors, no children, no fields.
--
--  Our pixels live on GHOSTS: mouse-disabled frames anchored TO each tab
--  (anchor-only, the sanctioned shape -- never parented to them). Anchors
--  resolve in the same render pass, so ghosts track Blizzard's layout
--  pixel-for-pixel with no one-frame lag, including mid-drag, and we never
--  measure a tab or a (possibly secret) label. Ghost text is display-only:
--  SetText accepts secrets; the fontstring is edge-anchored so long names
--  ellipsis-truncate instead of being measured.
--
--  Undocked windows and minimized pills keep their stock Blizzard tabs
--  visible and functional (native drag-to-redock, native menus); only the
--  docked strip is ghosted.
-------------------------------------------------------------------------------
local _, mod = ...
local CUI = _G.CludesUI
if not CUI then
    return
end

local CHAT = mod.ECHAT
if not CHAT then
    return
end

local CFD = CUI._chatCFD
if not CFD then
    return
end

local issecretvalue = _G.issecretvalue

local function DB()
    return CHAT.DB()
end

-- Style page (latched by the module root). Blizzard Style reveals Blizzard's
-- real docked tabs, so the docked ghosts stand down and the float ghosts stay
-- only as invisible motion catchers. Classic keeps the ghosts over the
-- invisible strip and paints them with the vanilla tab sheet at its native
-- 32px height (the strip's clip rect is raised to fit it).
local function BlizzTabs()
    return mod.ChatBlizzTabs and mod.ChatBlizzTabs()
end
local function ClassicTabs()
    return mod.ChatStyle and mod.ChatStyle() == "classic"
end
local CLASSIC_TAB_H = 32
local CLASSIC_CLIP_UP = CLASSIC_TAB_H - 26 -- the dock manager is 26 tall
local CLASSIC_LABEL_Y = -5 -- the sheet's label seat
local CLASSIC_IDLE_A = 0.75 -- an unselected tab's art
-- WoW Forever: ghosts wear the kit's bronze tab (CludesUIChat_Forever.lua)
-- at their own height, the strip's clip raised to fit it like Classic's.
local function FvTabs()
    return mod.ChatForever and mod.ChatForever()
end
local FV_TAB_H = 28
local FV_CLIP_UP = FV_TAB_H - 26
local FV_LABEL_Y = -2
local FV_LABEL_Y_HEAVY = -1 -- Border Style Heavy Bronze: the heavy tab's label seat

local function TabHeight()
    if ClassicTabs() then
        return CLASSIC_TAB_H
    end
    if FvTabs() then
        return FV_TAB_H
    end
    return DB().tabHeight or 24
end

local function TabFontPath()
    local conf = DB()
    local fontKey = conf.tabFont or "__global"
    if fontKey == "__global" then
        return (CUI.GetFontPath("chat")) or STANDARD_TEXT_FONT
    end
    return (CUI.ResolveFontName(fontKey)) or STANDARD_TEXT_FONT
end

-- Outline flag for the tab labels: the chat module's own resolver first (the Chat
-- page's Outline Mode picker overrides the module/global mode, same as the bubbles),
-- then the module font entry, then none.
local function TabFontFlag()
    return (CHAT.GetOutlineFlag and CHAT.GetOutlineFlag()) or (CUI.GetFontOutlineFlag("chat")) or ""
end

-- Resolve a color table honoring the shared custom/accent/class mode keys.
local function ResolveModeColor(mode, stored, fallback)
    if mode == "accent" and CUI.GetAccentColor then
        local red, green, blue = CUI.GetAccentColor()
        return red, green, blue, (stored and stored.a) or fallback.a or 1
    end
    if mode == "class" then
        local _, class = UnitClass("player")
        local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if color then
            return color.r, color.g, color.b, (stored and stored.a) or fallback.a or 1
        end
    end
    local color = stored or fallback
    local a = color.a
    if a == nil then
        a = fallback.a
    end
    if a == nil then
        a = 1
    end
    return color.r or 1, color.g or 1, color.b or 1, a
end

local function SelectedWindow()
    return GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
end

-------------------------------------------------------------------------------
--  Strip: a pure visual layer mirroring the dock manager's rect. It hosts the
--  ghosts (clipping them exactly where Blizzard clips scrolled-out tabs),
--  carries the module fade via _ApplyAlpha, and arms the interaction follower
--  through motion-only mouse flags -- clicks pass through to the real tabs.
-------------------------------------------------------------------------------
local tabStrip = CreateFrame("Frame", nil, UIParent)
tabStrip:SetFrameStrata("MEDIUM")
-- Level 100, like the old tab hosts: the panel border frame occupies MEDIUM
-- levels 96-98 across this exact band and must never draw over the tabs.
tabStrip:SetFrameLevel(100)
tabStrip:SetClipsChildren(true)
if tabStrip.SetMouseClickEnabled then
    tabStrip:SetMouseClickEnabled(false)
    tabStrip:SetMouseMotionEnabled(true)
    -- A motion-enabled frame still participates in click hit-testing and
    -- would swallow clicks meant for the (invisible) tabs beneath; propagate
    -- sends them through. Field-measured: without this, only the sliver of
    -- tab above the strip's rect was clickable.
    if tabStrip.SetPropagateMouseClicks then
        tabStrip:SetPropagateMouseClicks(true)
    end
    -- Motion propagates too: the tab under the cursor must keep receiving
    -- OnEnter/OnLeave (stock tab tooltip). Field-measured: without this the
    -- tooltip died the moment the cursor crossed into the strip's rect.
    if tabStrip.SetPropagateMouseMotion then
        tabStrip:SetPropagateMouseMotion(true)
    end
else
    tabStrip:EnableMouse(false)
end
tabStrip:SetScript("OnEnter", function()
    if CHAT.FollowArm then
        CHAT.FollowArm()
    end
    -- The strip sits above the idle-fade peek overlay and captures motion
    -- over the tab band; hovering the tabs counts as chat interaction.
    if CHAT.ResetIdleTimer then
        CHAT.ResetIdleTimer()
    end
end)
tabStrip:SetScript("OnLeave", function()
    if CHAT.FollowRelease then
        CHAT.FollowRelease()
    end
end)
tabStrip:Hide()
mod._chatTabStrip = tabStrip

local ghostList = {} -- pooled ghost frames, index = dock display order
local floatGhosts = {} -- per-window-id ghosts for undocked windows

-- LibChatAnims compat (DBM embeds it, among others): the lib REPLACES
-- Blizzard's tab-flash machinery to sidestep the UIFrameFlash shared-registry
-- taint, keeps alert state in its OWN table, and never writes tab.alerting --
-- IsAlerting(tab) is its published accessor for exactly this integration.
-- Lazily fetched: nil until some addon loads the lib (LibStub registry entry
-- is identity-stable across minor upgrades, so caching the ref is safe).
local libLCA
local function TabAlerting(tabBtn)
    if tabBtn.alerting then
        return true
    end
    -- Retail since 12.1.5 and WoW Forever keep the alert state off the tab,
    -- so a tainted message filter cannot taint it, and never write
    -- tab.alerting: ChatFrameUtil.IsTabAlerting is its reader there.
    local util = ChatFrameUtil
    if util and util.IsTabAlerting and util.IsTabAlerting(tabBtn) then
        return true
    end
    libLCA = libLCA or (LibStub and LibStub("LibChatAnims", true))
    return libLCA and libLCA:IsAlerting(tabBtn) and true or false
end
local floatSeen = {} -- wiped scratch set for the float surplus sweep

-- Scroll-region tabs live inside the dock's scroll window: on overflow
-- Blizzard SCROLLS them left and the scroll frame clips them at its left
-- edge (which sits at the last pinned tab's right edge). That region holds
-- EVERY docked tab except the pinned static pair (General, Combat Log) --
-- whisper tabs AND user-created persistent windows alike. Their ghosts must
-- clip at exactly the same edge, or a scrolled-out ghost renders on top of
-- the pinned tabs. This sub-container mirrors the scroll frame's horizontal
-- bounds with the strip's vertical bounds, live-anchored, so ghost clipping
-- tracks Blizzard's -- including partial clips during the scroll animation.
local dynamicClip = CreateFrame("Frame", nil, tabStrip)
dynamicClip:SetClipsChildren(true)
dynamicClip:EnableMouse(false)
local dynClipAnchored = false
local function EnsureDynClip()
    if dynClipAnchored then
        return true
    end
    local dock = _G.GENERAL_CHAT_DOCK
    local scroller = dock and dock.scrollFrame
    if not scroller then
        return false
    end
    dynamicClip:SetPoint("TOP", tabStrip, "TOP", 0, 0)
    dynamicClip:SetPoint("BOTTOM", tabStrip, "BOTTOM", 0, 0)
    dynamicClip:SetPoint("LEFT", scroller, "LEFT", 0, 0)
    dynamicClip:SetPoint("RIGHT", scroller, "RIGHT", 0, 0)
    dynClipAnchored = true
    return true
end

local RequestRefresh -- forward declaration

-------------------------------------------------------------------------------
--  Ghost pool
-------------------------------------------------------------------------------
local function BuildGhost()
    local g = CreateFrame("Frame", nil, tabStrip)
    g:EnableMouse(false)

    local backdrop = g:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    g._bg = backdrop

    local fontStr = g:CreateFontString(nil, "OVERLAY")
    -- Edge-anchored: the label is clamped to the ghost's (= tab's) width and
    -- ellipsis-truncates. Nothing is ever measured -- widths are Blizzard's,
    -- and whisper labels can be SECRET values.
    fontStr:SetWordWrap(false)
    fontStr:SetJustifyH("CENTER")
    -- A bare fontstring has NO font: SetText before a SetFont is a hard error.
    fontStr:SetFont(TabFontPath(), DB().tabFontSize or 11, TabFontFlag())
    g._fs = fontStr

    local Pix = CUI.PP
    local onePx = (Pix and Pix.mult) or 1

    local underlineTex = g:CreateTexture(nil, "OVERLAY", nil, 7)
    underlineTex:SetHeight(onePx)
    underlineTex:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", 0, 0)
    underlineTex:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", 0, 0)
    underlineTex:Hide()
    if Pix and Pix.DisablePixelSnap then
        Pix.DisablePixelSnap(underlineTex)
    end
    g._underline = underlineTex

    local separator = g:CreateTexture(nil, "OVERLAY", nil, 7)
    separator:SetWidth(onePx)
    separator:SetPoint("TOPLEFT", g, "TOPRIGHT", 0, 0)
    separator:SetPoint("BOTTOMLEFT", g, "BOTTOMRIGHT", 0, 0)
    separator:Hide()
    if Pix and Pix.DisablePixelSnap then
        Pix.DisablePixelSnap(separator)
    end
    g._sep = separator

    local borderHost = CreateFrame("Frame", nil, g)
    borderHost:SetAllPoints()
    borderHost:EnableMouse(false)
    g._borderHost = borderHost

    -- Whisper alert: Blizzard's own art and cadence. Stock breathes the
    -- tab.glow texture (ChatFrameTab-NewMessage, ADD blend) via
    -- UIFrameFlash(1s in, 1s out, infinite); this is a copy on OUR texture
    -- driven by OUR AnimationGroup -- never their region (their flash
    -- machinery writes it) and never UIFrameFlash (shared registry).
    local glowTex = g:CreateTexture(nil, "OVERLAY", nil, 6)
    glowTex:SetTexture("Interface\\ChatFrame\\ChatFrameTab-NewMessage")
    glowTex:SetBlendMode("ADD")
    -- Desaturated so StyleGhost's vertex color tints it cleanly to the
    -- tab's text color instead of multiplying against the orange art.
    glowTex:SetDesaturated(true)
    glowTex:SetPoint("TOPLEFT", g, "TOPLEFT", 8, -11)
    glowTex:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", -8, 0)
    glowTex:Hide()
    g._glow = glowTex
    -- Zero idle cost: the group runs C-side only while flashing; Start/Stop
    -- are guarded so repeat alerts never restart the animation.
    local flasher = glowTex:CreateAnimationGroup()
    flasher:SetLooping("BOUNCE")
    local fade = flasher:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.25)
    fade:SetToAlpha(0.75)
    fade:SetDuration(0.5)
    g._flasher = flasher

    function g:StartFlash()
        if not self._flasher:IsPlaying() then
            self._glow:Show()
            self._flasher:Play()
        end
    end
    function g:StopFlash()
        if self._flasher:IsPlaying() then
            self._flasher:Stop()
        end
        self._glow:Hide()
    end

    return g
end

local function AcquireGhost(tabIndex)
    local g = ghostList[tabIndex]
    if g then
        return g
    end
    g = BuildGhost()
    ghostList[tabIndex] = g
    return g
end

-------------------------------------------------------------------------------
--  Undocked tabs: no container sits between them and UIParent, and per-tab
--  FRAME alpha is rewritten constantly by FCFTab_UpdateAlpha -- but nothing
--  in Blizzard code writes the REGIONS' own alpha channel (the frame alpha
--  and SetTextColor ride different slots). One-way region SetAlpha(0) is the
--  same suppression class as the FontStringContainer: C-state only, nothing
--  secure ever reads it, re-asserted by the sweep in case a vertex-color
--  path ever touches an art texture's alpha slot.
-------------------------------------------------------------------------------
local function SuppressTabRegions(tabBtn)
    local regions = { tabBtn:GetRegions() }
    for tabIndex = 1, #regions do
        local regionFrame = regions[tabIndex]
        -- GetAlpha reads secret on chat-roleset widgets in lockdown; a
        -- secret skips the compare and re-asserts.
        local a = regionFrame and regionFrame.SetAlpha and regionFrame:GetAlpha()
        if a and ((issecretvalue and issecretvalue(a)) or a ~= 0) then
            regionFrame:SetAlpha(0)
        end
    end
end

-- Blizzard Style keeps undocked tabs visible, but they are UIParent children
-- that no chat fade or full hide reaches: while chat is fully hidden their
-- regions are zeroed like the CludesUI look's, recording exactly which
-- ones were visible, and those alone come back on reveal. The tab is flagged
-- (CFD) while it holds recorded regions, so the reveal restores it whatever
-- its dock state by then (Blizzard can re-dock a pooled whisper frame while
-- chat is hidden) and skips every tab with nothing recorded.
local stockTabRegionsOff = setmetatable({}, { __mode = "k" })
local function StockHideTabRegions(tabBtn)
    local regions = { tabBtn:GetRegions() }
    for tabIndex = 1, #regions do
        local regionFrame = regions[tabIndex]
        local a = regionFrame and regionFrame.SetAlpha and regionFrame:GetAlpha()
        if a and not stockTabRegionsOff[regionFrame] and ((issecretvalue and issecretvalue(a)) or a ~= 0) then
            stockTabRegionsOff[regionFrame] = true
            CFD(tabBtn).stockRegionsOff = true
            regionFrame:SetAlpha(0)
        end
    end
end
local function StockRestoreTabRegions(tabBtn)
    local skinData = CFD(tabBtn)
    if not skinData.stockRegionsOff then
        return
    end
    skinData.stockRegionsOff = nil
    local regions = { tabBtn:GetRegions() }
    for tabIndex = 1, #regions do
        local regionFrame = regions[tabIndex]
        if regionFrame and stockTabRegionsOff[regionFrame] then
            stockTabRegionsOff[regionFrame] = nil
            regionFrame:SetAlpha(1)
        end
    end
end

-------------------------------------------------------------------------------
--  Ghost styling: everything the owned strip drew, unchanged, minus any
--  geometry authority.
-------------------------------------------------------------------------------
local function StyleGhost(g, active)
    local conf = DB()
    local status = g.state
    local fontStr = g._fs

    fontStr:SetFont(TabFontPath(), conf.tabFontSize or 11, TabFontFlag())
    local tr, tg, tb, ta
    if status.isTemp then
        -- Conversation tabs keep the whisper chat color as their marker,
        -- like the old skin (which left Blizzard's coloring in place).
        local details = ChatTypeInfo[status.bn and "BN_WHISPER" or "WHISPER"]
        tr, tg, tb, ta =
            (details and details.r) or 1, (details and details.g) or 0.5, (details and details.b) or 1, 1
    elseif active then
        tr, tg, tb, ta = ResolveModeColor(
            conf.tabFontColorActiveMode or "custom",
            conf.tabFontColorActive,
            { r = 1, g = 1, b = 1, a = 1 }
        )
    else
        tr, tg, tb, ta = ResolveModeColor(
            conf.tabFontColorMode or "custom",
            conf.tabFontColor,
            { r = 1, g = 1, b = 1, a = 0.65 }
        )
    end
    fontStr:SetTextColor(tr, tg, tb, ta)
    -- The alert glow wears the tab's text color (desaturated art + tint).
    g._glow:SetVertexColor(tr, tg, tb)

    -- Classic WoW UI: the vanilla chat tab sheet, cut the way retail's own
    -- chat config tabs still cut it (16px caps, a stretched middle), dimmed
    -- while not selected. Typography stays the user's. Built once per ghost.
    if ClassicTabs() then
        if not g._clL then
            local TEX = "Interface\\ChatFrame\\ChatFrameTab"
            local L = g:CreateTexture(nil, "BACKGROUND", nil, 1)
            L:SetTexture(TEX)
            L:SetTexCoord(0, 0.25, 0, 1)
            L:SetSize(16, CLASSIC_TAB_H)
            L:SetPoint("TOPLEFT", g, "TOPLEFT", 0, 0)
            local R = g:CreateTexture(nil, "BACKGROUND", nil, 1)
            R:SetTexture(TEX)
            R:SetTexCoord(0.75, 1, 0, 1)
            R:SetSize(16, CLASSIC_TAB_H)
            R:SetPoint("TOPRIGHT", g, "TOPRIGHT", 0, 0)
            local M = g:CreateTexture(nil, "BACKGROUND", nil, 1)
            M:SetTexture(TEX)
            M:SetTexCoord(0.25, 0.75, 0, 1)
            M:SetPoint("TOPLEFT", L, "TOPRIGHT", 0, 0)
            M:SetPoint("BOTTOMRIGHT", R, "BOTTOMLEFT", 0, 0)
            g._clL, g._clM, g._clR = L, M, R
            g._bg:Hide()
            g._underline:Hide()
            g._sep:Hide()
            g._borderHost:Hide()
        end
        local a = active and 1 or CLASSIC_IDLE_A
        g._clL:SetAlpha(a)
        g._clM:SetAlpha(a)
        g._clR:SetAlpha(a)
        return
    end

    -- WoW Forever: the kit's bronze tab, warm while selected. Typography
    -- stays the user's.
    if FvTabs() then
        CHAT.FV_StyleGhost(g, active)
        return
    end

    -- Background: color or texture, active/inactive variants.
    local bgColor
    if active then
        local stored = conf.tabBackgroundColorActive or { r = 0.03, g = 0.045, b = 0.05, a = 0.65 }
        local br, bgc2, bb, ba = ResolveModeColor(
            conf.tabBackgroundColorActiveMode or "custom",
            stored,
            { r = 0.03, g = 0.045, b = 0.05, a = 0.65 }
        )
        bgColor = { r = br, g = bgc2, b = bb, a = ba }
    else
        local color = conf.tabBackgroundColor or { r = 0.03, g = 0.045, b = 0.05, a = 0.44 }
        bgColor = { r = color.r or 0.03, g = color.g or 0.045, b = color.b or 0.05, a = color.a == nil and 0.44 or color.a }
    end
    local texKey = conf.tabBackgroundTexture or "none"
    local texPath
    if texKey ~= "none" then
        if CHAT.RefreshBgTextureCatalogue then
            CHAT.RefreshBgTextureCatalogue()
        end
        if CUI.ResolveTexturePath then
            texPath = CUI.ResolveTexturePath(mod.chatBgTextures, texKey, nil)
        else
            texPath = mod.chatBgTextures and mod.chatBgTextures[texKey]
        end
    end
    if texPath then
        g._bg:SetTexture(texPath)
        g._bg:SetVertexColor(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
    else
        g._bg:SetVertexColor(1, 1, 1, 1)
        g._bg:SetColorTexture(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
    end

    -- Active underline.
    local underlineTex = g._underline
    if conf.activeUnderline ~= false and active then
        local mode = conf.activeUnderlineColorMode or "accent"
        if mode == "border" then
            mode = "custom"
        end
        local ur, ug, ub, ua =
            ResolveModeColor(mode, conf.activeUnderlineColor, { r = 0.05, g = 0.82, b = 0.61, a = 1 })
        underlineTex:SetColorTexture(ur, ug, ub, ua)
        underlineTex:Show()
    else
        underlineTex:Hide()
    end

    -- Separator (extended mode): the 1px divider in Blizzard's inter-tab gap.
    local showSep = CHAT.ExtendBgBehindTabs(conf) and not conf.hideBorders
    if showSep then
        local region, gg, b, a
        if conf.innerBorderColorMode == "accent" and CUI.GetAccentColor then
            region, gg, b = CUI.GetAccentColor()
            a = (conf.innerBorderColor and conf.innerBorderColor.a) or 0.06
        else
            local color = conf.innerBorderColor or { r = 1, g = 1, b = 1, a = 0.06 }
            region, gg, b, a = color.r or 1, color.g or 1, color.b or 1, color.a == nil and 0.06 or color.a
        end
        g._sep:SetColorTexture(region, gg, b, a)
        g._sep:Show()
    else
        g._sep:Hide()
    end

    -- Per-tab border (only when tabs are visual islands outside the panel).
    local owner = g._borderHost
    if CUI.ApplyBorderStyle then
        local showBorder = not CHAT.ExtendBgBehindTabs(conf)
        local sync = conf.syncTabBorder ~= false
        local prefixText = sync and "panelBorder" or "tabBorder"
        local function K(suffix, fallback)
            local val = conf[prefixText .. suffix]
            if val == nil then
                return fallback
            end
            return val
        end
        local sizes = { none = 0, thin = 1, normal = 2, heavy = 3, strong = 4 }
        local thicknessKey = K("Thickness", "none")
        local size = sizes[thicknessKey] or 1
        local texKey = K("Texture", "solid")
        -- Exact pixel size under the same prefix as the step (nil = the legacy
        -- step path); the hidden 0 passed below is a substitute, so no px then.
        local px = showBorder and CUI.BorderPx(K("ThicknessPx", nil), size, texKey) or nil
        local br, bgr, bb, ba = ResolveModeColor(K("ColorMode", "custom"), K("Color", nil), {
            r = 1,
            g = 1,
            b = 1,
            a = K("Opacity", nil) or ((K("ColorMode", "custom") == "custom") and 0.18 or 0.5),
        })
        if conf.activeTabBorder ~= false and active and conf.tabBorderColorActive then
            local ac = conf.tabBorderColorActive
            br, bgr, bb = ac.r or br, ac.g or bgr, ac.b or bb
            ba = ac.a == nil and ba or ac.a
        end
        CUI.ApplyBorderStyle(
            owner,
            showBorder and size or 0,
            br,
            bgr,
            bb,
            ba,
            texKey,
            K("OffsetX", nil),
            K("OffsetY", nil),
            K("ShiftX", nil),
            K("ShiftY", nil),
            "chat",
            thicknessKey,
            nil,
            px
        )
        owner:SetShown(showBorder and size > 0)
    end
end

-------------------------------------------------------------------------------
--  Float ghost refresh (file-scope, explicit args: no per-refresh closure).
-------------------------------------------------------------------------------
-- Float ghosts arm the geometry follower themselves -- the strip's motion
-- catcher only covers the dock band, and the armed follower is what makes
-- this window's panel (and the text frame anchored inside it) follow a native
-- tab drag per-frame instead of freezing until the next deferred pass.
-- Motion-only + full propagation: the tab beneath keeps its tooltip, clicks,
-- and the drag itself. The propagation calls are blocked in combat on every
-- frame, so a ghost first built in combat stays mouse-less (clicks and hover
-- reach the tab; only the follower waits) until combat ends.
local function ArmGhostMouse(g)
    g._mouseArmed = true
    if not g.SetMouseClickEnabled then
        return
    end
    g:SetMouseClickEnabled(false)
    g:SetMouseMotionEnabled(true)
    if g.SetPropagateMouseClicks then
        g:SetPropagateMouseClicks(true)
    end
    if g.SetPropagateMouseMotion then
        g:SetPropagateMouseMotion(true)
    end
    g:SetScript("OnEnter", function()
        if CHAT.FollowArm then
            CHAT.FollowArm()
        end
        if CHAT.ResetIdleTimer then
            CHAT.ResetIdleTimer()
        end
    end)
    g:SetScript("OnLeave", function()
        if CHAT.FollowRelease then
            CHAT.FollowRelease()
        end
    end)
end

local function ArmPendingGhosts()
    for _, g in pairs(floatGhosts) do
        if not g._mouseArmed then
            ArmGhostMouse(g)
        end
    end
end

local function RefreshFloatGhost(castFrame, height, fontFile, fontSize, padX, labelY, seen)
    local ident = castFrame:GetID()
    local tabBtn = _G[castFrame:GetName() .. "Tab"]
    local skinData = CFD(castFrame)
    if not (tabBtn and skinData and skinData.bg) then
        return
    end
    local g = floatGhosts[ident]
    if not g then
        g = BuildGhost()
        floatGhosts[ident] = g
    end
    if not g._mouseArmed then
        if InCombatLockdown() then
            mod.CombatQueue.Defer(ArmPendingGhosts, ArmPendingGhosts)
        else
            ArmGhostMouse(g)
        end
    end
    if g:GetParent() ~= skinData.bg then
        g:SetParent(skinData.bg)
    end
    local isTemp = castFrame.isTemporary and true or false
    local st = g.state
    if not st then
        st = {}
        g.state = st
    end
    st.cf, st.id, st.isTemp, st.bn = castFrame, ident, isTemp, nil
    g:ClearAllPoints()
    g:SetPoint("BOTTOMLEFT", tabBtn, "BOTTOMLEFT", 0, 0)
    g:SetPoint("BOTTOMRIGHT", tabBtn, "BOTTOMRIGHT", 0, 0)
    g:SetHeight(height)
    if BlizzTabs() then
        -- Blizzard's own tab is the visible one here: the ghost stays only as
        -- the invisible motion catcher that keeps the panel following drags.
        if g:GetAlpha() ~= 0 then
            g:SetAlpha(0)
        end
        g:Show()
        seen[ident] = true
        return
    end
    local fontStr = g._fs
    fontStr:SetFont(fontFile, fontSize, TabFontFlag())
    fontStr:ClearAllPoints()
    fontStr:SetPoint("LEFT", g, "LEFT", padX, labelY)
    fontStr:SetPoint("RIGHT", g, "RIGHT", -padX, labelY)
    if isTemp then
        -- Same secret discipline as the docked path.
        local labelText = castFrame.chatTarget
        st.bn = castFrame.chatType == "BN_WHISPER"
        if issecretvalue and issecretvalue(labelText) then
            fontStr:SetText(labelText)
        elseif labelText ~= nil then
            fontStr:SetText(labelText)
        else
            fontStr:SetText("...")
        end
    else
        local name = GetChatWindowInfo(ident)
        fontStr:SetText(name or ("Window " .. ident))
    end
    StyleGhost(g, castFrame:IsShown())
    g:Show()
    seen[ident] = true
end

-------------------------------------------------------------------------------
--  Strip placement: mirror the dock manager's rect exactly (live anchors).
-------------------------------------------------------------------------------
local function PositionStrip()
    local dockManager = _G.GeneralDockManager
    if not dockManager then
        return
    end
    tabStrip:ClearAllPoints()
    -- Classic's full-height tabs (and WoW Forever's) reach above the 26px
    -- dock: raise the clip.
    tabStrip:SetPoint(
        "TOPLEFT",
        dockManager,
        "TOPLEFT",
        0,
        ClassicTabs() and CLASSIC_CLIP_UP or (FvTabs() and FV_CLIP_UP) or 0
    )
    tabStrip:SetPoint("BOTTOMRIGHT", dockManager, "BOTTOMRIGHT", 0, 0)
    -- Never re-show over an engaged full hide or passthrough: their
    -- remember-restores own the reveal.
    tabStrip:SetShown(not mod._chatStackHidden and not mod._chatPassthrough)
end

-------------------------------------------------------------------------------
--  Refresh: enumerate the dock (reads only), anchor one ghost per docked tab.
--  Geometry is entirely Blizzard's; a ghost follows its tab through every
--  move, resize, drag, and scroll in the same render pass.
-------------------------------------------------------------------------------
local function RefreshNow()
    PositionStrip()
    local conf = DB()
    local selected = SelectedWindow()
    local height = TabHeight()
    local fontFile = TabFontPath()
    local fontSize = conf.tabFontSize or 11
    local fontFlag = TabFontFlag()
    local padX = conf.tabInnerPaddingX or 12
    local labelY = ClassicTabs() and CLASSIC_LABEL_Y
        or (FvTabs() and (mod.ChatFvHeavy() and FV_LABEL_Y_HEAVY or FV_LABEL_Y))
        or 0

    -- The chat panel extends left of ChatFrame1 by its inset while Blizzard's
    -- dock starts at the frame edge; the FIRST ghost (and the strip's clip
    -- rect) stretch left to the panel edge so the row lines up with the
    -- panel. Visual-only: the extra pixels have no tab under them. Deferred
    -- numeric rect reads, the module's shipped-safe class. The stock styles
    -- draw no panel, so their tabs stay exactly where Blizzard puts them;
    -- WoW Forever draws one, its first tab standing tabX in from its frame.
    local leftExtend = 0
    local fvTabs = FvTabs()
    if not (mod.ChatStock and mod.ChatStock()) or fvTabs then
        local cf1 = _G.ChatFrame1
        local bg1 = cf1 and CFD(cf1).bg
        local firstCF = GENERAL_CHAT_DOCK
            and GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES
            and GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES[1]
        local firstTab = firstCF and _G[firstCF:GetName() .. "Tab"]
        local bgLeft = bg1 and bg1:GetLeft()
        local tabLeft = firstTab and firstTab:GetLeft()
        if bgLeft and tabLeft then
            if fvTabs then
                bgLeft = bgLeft + CHAT.FV.tabX
            end
            local delta = bgLeft - tabLeft
            if delta < 0 and delta > -60 then
                leftExtend = delta
            end
        end
    end
    if leftExtend ~= 0 then
        local dockManager = _G.GeneralDockManager
        if dockManager then
            tabStrip:SetPoint("TOPLEFT", dockManager, "TOPLEFT", leftExtend, fvTabs and FV_CLIP_UP or 0)
        end
    end

    -- The dock's scroll child parents every SCROLLING tab (all docked tabs
    -- except pinned General/Combat Log). Real parentage is the clip
    -- discriminator below -- read fresh each pass, tabs redock and reorder.
    local scrollChild
    do
        local scroller = GENERAL_CHAT_DOCK and GENERAL_CHAT_DOCK.scrollFrame
        scrollChild = scroller and scroller.GetScrollChild and scroller:GetScrollChild() or nil
    end

    local dockList = GENERAL_CHAT_DOCK and GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES
    local total = 0
    local seenScrolling = false
    local tabGap = (conf.tabSpacing or 1) * ((CUI.PP and CUI.PP.mult) or 1)
    -- Blizzard Style shows Blizzard's real docked tabs: no docked ghosts (the
    -- sweep below hides any left from the pool).
    if type(dockList) == "table" and not BlizzTabs() then
        for tabIndex = 1, #dockList do
            local castFrame = dockList[tabIndex]
            local tabBtn = castFrame and _G[castFrame:GetName() .. "Tab"]
            if tabBtn then
                total = total + 1
                local g = AcquireGhost(total)
                local isTemp = castFrame.isTemporary and true or false
                -- State tables are reused across refreshes (no alloc churn).
                local st = g.state
                if not st then
                    st = {}
                    g.state = st
                end
                st.cf, st.id, st.isTemp, st.bn = castFrame, castFrame:GetID(), isTemp, nil

                -- Ghosts of scroll-region tabs clip at the dock scroll
                -- window's edges, like their tabs; only the pinned static
                -- pair's ghosts clip at the strip's. User-created persistent
                -- windows scroll exactly like whisper tabs, so the
                -- discriminator is the tab's REAL parent (the scroll
                -- child), never the temporary flag.
                local wantParent = tabStrip
                local isScrolling = scrollChild and tabBtn:GetParent() == scrollChild
                if isScrolling and EnsureDynClip() then
                    wantParent = dynamicClip
                end
                if g:GetParent() ~= wantParent then
                    g:SetParent(wantParent)
                end

                -- FCFDock_UpdateTabs leaves one UI unit between tabs in each
                -- group, but none before the first scrolling tab. Compensate
                -- on our visual only; never re-anchor Blizzard's click targets.
                local nativeGap = isScrolling and not seenScrolling and 0 or 1
                if isScrolling then
                    seenScrolling = true
                end
                local leftInset = total == 1 and leftExtend or 0
                -- Classic and WoW Forever ghosts span their tab exactly (their
                -- art carries its own margins), so no spacing compensation there.
                if total > 1 and not CHAT.ExtendBgBehindTabs(conf) and not ClassicTabs() and not FvTabs() then
                    leftInset = tabGap - nativeGap
                end

                g:ClearAllPoints()
                local band = mod._chatBgExt
                if band and band:IsShown() then
                    -- Band mode: vertical extent from the band frame ITSELF
                    -- (horizontal from the tab), with ONE PHYSICAL PIXEL of
                    -- top slack. The inset chain runs on raw UI units, so at
                    -- non-1 scales every derived edge sits at its own
                    -- physical-pixel fraction and per-texture rounding can
                    -- push a flush-rect fill one row above the band's
                    -- rendered top (field-isolated to the bg fill; rect
                    -- sharing alone did not close it). Starting the ghost a
                    -- pixel inside the band makes poking above impossible
                    -- at any position or scale; the slack row reads as band
                    -- background.
                    local onePx = (CUI.PP and CUI.PP.mult) or 1
                    g:SetPoint("TOP", band, "TOP", 0, -onePx)
                    g:SetPoint("BOTTOM", band, "BOTTOM", 0, 0)
                    g:SetPoint("LEFT", tabBtn, "LEFT", total == 1 and leftExtend or 0, 0)
                    g:SetPoint("RIGHT", tabBtn, "RIGHT", 0, 0)
                else
                    -- Island tabs: bottom-aligned to the tab, our height.
                    g:SetPoint("BOTTOMLEFT", tabBtn, "BOTTOMLEFT", leftInset, 0)
                    g:SetPoint("BOTTOMRIGHT", tabBtn, "BOTTOMRIGHT", 0, 0)
                    g:SetHeight(height)
                end

                local fontStr = g._fs
                fontStr:SetFont(fontFile, fontSize, fontFlag)
                fontStr:ClearAllPoints()
                fontStr:SetPoint("LEFT", g, "LEFT", padX, labelY)
                fontStr:SetPoint("RIGHT", g, "RIGHT", -padX, labelY)

                if isTemp then
                    -- Conversation label: may be a SECRET value. issecretvalue
                    -- comes FIRST (even a nil-compare on a secret errors);
                    -- secrets go straight to SetText, the display-only sink.
                    local labelText = castFrame.chatTarget
                    g.state.bn = castFrame.chatType == "BN_WHISPER"
                    if issecretvalue and issecretvalue(labelText) then
                        fontStr:SetText(labelText)
                    elseif labelText ~= nil then
                        fontStr:SetText(labelText)
                    else
                        fontStr:SetText("...")
                    end
                else
                    local name = GetChatWindowInfo(castFrame:GetID())
                    fontStr:SetText(name or ("Window " .. castFrame:GetID()))
                end

                local active = castFrame == selected
                StyleGhost(g, active)
                -- Blizzard's own alert state is authoritative here: their
                -- handler sets it the moment a flash-worthy message hits a
                -- hidden window (including the message that CREATES a
                -- conversation window -- our ghost is born one pass later
                -- and would miss the observer's flash), and clears it on
                -- select. Read through TabAlerting, never tab.alerting
                -- directly: under a LibChatAnims embedder, and on WoW
                -- Forever, the field stays nil forever, and this mirror then
                -- STOPPED the flash the observer lane had just started --
                -- whisper alerts died within one tab pass.
                if active then
                    g:StopFlash()
                elseif TabAlerting(tabBtn) then
                    g:StartFlash()
                else
                    g:StopFlash()
                end
                g:Show()
            end
        end
    end
    for tabIndex = total + 1, #ghostList do
        local g = ghostList[tabIndex]
        if g.state then
            g.state.cf = nil
        end
        g:StopFlash()
        g:Hide()
    end

    -- Undocked windows: one ghost pinned to each window's (region-suppressed)
    -- tab, parented to that window's panel so it inherits the panel's shown
    -- state and fade. The tab itself stays fully live: native drag-to-redock,
    -- menu, tooltip.
    table.wipe(floatSeen)
    for tabIndex = 1, 10 do
        local castFrame = _G["ChatFrame" .. tabIndex]
        if castFrame and not castFrame.isDocked and castFrame:IsShown() then
            RefreshFloatGhost(castFrame, height, fontFile, fontSize, padX, labelY, floatSeen)
        end
    end
    local frameList = _G.CHAT_FRAMES
    if type(frameList) == "table" then
        for tabIndex = 11, #frameList do
            local castFrame = _G[frameList[tabIndex]]
            if
                castFrame
                and castFrame.isTemporary
                and castFrame.inUse
                and not castFrame.isDocked
                and castFrame:IsShown()
            then
                RefreshFloatGhost(castFrame, height, fontFile, fontSize, padX, labelY, floatSeen)
            end
        end
    end
    for ident, g in pairs(floatGhosts) do
        if not floatSeen[ident] then
            if g.state then
                g.state.cf = nil
            end
            g:StopFlash()
            g:Hide()
        end
    end
end

local refreshQueued = false
RequestRefresh = function()
    if refreshQueued then
        return
    end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        RefreshNow()
    end)
end
CHAT.TabsRefresh = RequestRefresh
CHAT.TabsRefreshNow = RefreshNow

-------------------------------------------------------------------------------
--  Adopt Blizzard's strip: invisible but fully clickable. One container-alpha
--  write; per-tab alphas multiply against it so FCFTab_UpdateAlpha can keep
--  writing whatever it likes. The overflow button and its list pop back to
--  full visibility (stock look) via ignoreParentAlpha -- without it they
--  would be invisible click targets.
--
--  Passthrough / full hide: invisible tabs must not eat world clicks, so the
--  exact set (each docked tab + the overflow button) gets click-disabled
--  while either mode is engaged; the sweep re-asserts on late joiners.
-------------------------------------------------------------------------------
local function SetTabClickable(tabBtn, enabled)
    if not tabBtn.SetMouseClickEnabled then
        return
    end
    -- Temporary whisper tabs are PROTECTED in lockdown; a refused write is
    -- left for a later sweep (the tracker records only what actually
    -- landed, so the next TabsSweepBlizzard still sees the drift).
    if InCombatLockdown() then
        if not pcall(tabBtn.SetMouseClickEnabled, tabBtn, enabled) then
            return
        end
    else
        tabBtn:SetMouseClickEnabled(enabled)
    end
    if CFD then
        CFD(tabBtn).clickOff = (not enabled) or nil
    end
end

function CHAT.TabsSweepBlizzard()
    local dockManager = _G.GeneralDockManager
    local blizzTabs = BlizzTabs()
    if dockManager then
        -- Full hide owns the dock's shown state (SetChatStackShown hides it
        -- with a remember); the sweep only heals a wrongly-hidden dock when
        -- no full hide is engaged.
        if not dockManager:IsShown() and not mod._chatStackHidden then
            -- Ancestor Show with a protected docked whisper tab is blocked
            -- in lockdown; a refused heal retries on the next sweep.
            if InCombatLockdown() then
                pcall(dockManager.Show, dockManager)
            else
                dockManager:Show()
            end
        end
    end
    -- Blizzard Style: the real strip is the visible one; the module fade
    -- drives its dock alpha (_ApplyAlpha), and the overflow button inherits
    -- it like stock, so the invisible-strip asserts below do not apply.
    if dockManager and not blizzTabs then
        -- GetAlpha can return a secret number mid-combat in a raid (same
        -- class as the cursor-position guards elsewhere in this file); a
        -- secret result can't be safely compared for the ~= 0 skip-optimization,
        -- so just re-assert 0 unconditionally in that case.
        local gdmAlpha = dockManager:GetAlpha()
        if issecretvalue and issecretvalue(gdmAlpha) then
            dockManager:SetAlpha(0)
        elseif gdmAlpha ~= 0 then
            dockManager:SetAlpha(0)
        end
        local otherBtn = dockManager.overflowButton
        if otherBtn then
            if otherBtn.SetIgnoreParentAlpha and not otherBtn:IsIgnoringParentAlpha() then
                otherBtn:SetIgnoreParentAlpha(true)
            end
            local entries = otherBtn.list
            if entries and entries.SetIgnoreParentAlpha and not entries:IsIgnoringParentAlpha() then
                entries:SetIgnoreParentAlpha(true)
            end
        end
    end

    -- Click-state for the interaction plane, exact set, both directions.
    local wantOff = (mod._chatPassthrough or mod._chatStackHidden) and true or false
    local dockList = GENERAL_CHAT_DOCK and GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES
    if type(dockList) == "table" then
        for tabIndex = 1, #dockList do
            local castFrame = dockList[tabIndex]
            local tabBtn = castFrame and _G[castFrame:GetName() .. "Tab"]
            if tabBtn then
                local isOff = CFD(tabBtn).clickOff and true or false
                if isOff ~= wantOff then
                    SetTabClickable(tabBtn, not wantOff)
                end
            end
        end
    end
    if dockManager and dockManager.overflowButton then
        local otherBtn = dockManager.overflowButton
        local isOff = CFD(otherBtn).clickOff and true or false
        if isOff ~= wantOff then
            SetTabClickable(otherBtn, not wantOff)
        end
    end

    -- Undocked windows: suppress their tabs' region pixels (ghosts paint
    -- instead; re-asserted every sweep in case a vertex-color path touches
    -- an art texture's alpha slot) and mirror the passthrough click-state.
    for tabIndex = 1, 20 do
        local castFrame = _G["ChatFrame" .. tabIndex]
        local tabBtn = castFrame and _G["ChatFrame" .. tabIndex .. "Tab"]
        if tabBtn then
            -- Blizzard Style reveal: any tab still holding zeroed regions,
            -- docked or not (see StockHideTabRegions).
            if blizzTabs and not wantOff then
                StockRestoreTabRegions(tabBtn)
            end
            if not castFrame.isDocked then
                if not blizzTabs then
                    SuppressTabRegions(tabBtn)
                elseif wantOff and tabBtn:IsShown() then
                    StockHideTabRegions(tabBtn)
                end
                local isOff = CFD(tabBtn).clickOff and true or false
                if isOff ~= wantOff then
                    SetTabClickable(tabBtn, not wantOff)
                end
            end
        end
    end
    -- Blizzard Style: the quick-button bar keeps its stock parent (the
    -- visible combat log tab), exactly as Blizzard draws it.
    if blizzTabs then
        return
    end

    -- Combat log quick-button bar: Blizzard parents it to ChatFrame2Tab at
    -- its OnLoad purely for tab-alpha inheritance; under the alpha-0 dock it
    -- would inherit invisibility. Re-home it onto ChatFrame2 itself -- the
    -- frame its anchors already target -- keeping the tree fully
    -- Blizzard-owned (its secure Show/Hide and progress-bar writes never
    -- cross an insecure parent). Position is stock; it rides the chat fade
    -- via cf2's alpha and the frame's own dock show/hide. Idempotent;
    -- self-heals if the combat log addon loads (and re-parents) after a
    -- sweep.
    local qb = _G.CombatLogQuickButtonFrame_Custom
    local cf2 = _G.ChatFrame2
    if qb and cf2 and qb:GetParent() ~= cf2 then
        qb:SetParent(cf2)
    end
end

-------------------------------------------------------------------------------
--  Flash: driven by the engine tail. Suppression semantics come free -- a
--  message suppressed by Blizzard's handler never reaches AddMessage, so it
--  never reaches this observer. New conversation tabs appear via the same
--  observer (their first message queues a refresh).
-------------------------------------------------------------------------------
-- Whisper types only, matching Blizzard's FlashTabIfNotShown: the flashTab /
-- flashTabOnGeneral flags gate it AND the type must be a whisper.
local FLASH_TYPES = {
    WHISPER = true,
    BN_WHISPER = true,
    WHISPER_INFORM = false,
    BN_WHISPER_INFORM = false,
}

local function GhostFor(castFrame)
    for tabIndex = 1, #ghostList do
        local g = ghostList[tabIndex]
        if g.state and g.state.cf == castFrame then
            return g
        end
    end
    for _, g in pairs(floatGhosts) do
        if g.state and g.state.cf == castFrame then
            return g
        end
    end
    return nil
end

local function OnTabMessage(castFrame, evt)
    -- Blizzard Style: Blizzard's own tabs flash natively and docked windows
    -- have no ghost at all; only a shown undocked window still wants its
    -- (invisible, motion-catching) float ghost.
    if BlizzTabs() then
        if not castFrame.isDocked and castFrame:IsShown() and not GhostFor(castFrame) then
            RequestRefresh()
        end
        return
    end
    -- A message for a window with no ghost yet (fresh temp frame, or a dock
    -- change we have not seen) re-enumerates on the next tick. Hidden
    -- undocked windows are excluded: they get no ghost until shown, and
    -- re-queueing per message would churn.
    if not GhostFor(castFrame) and (castFrame.isDocked or castFrame:IsShown()) then
        RequestRefresh()
    end
    if not evt then
        return
    end
    local chatType = strsub(evt, 10)
    if not FLASH_TYPES[chatType] then
        return
    end
    local selected = SelectedWindow()
    if castFrame == selected or not castFrame.isDocked then
        return
    end
    local details = ChatTypeInfo[chatType]
    if not details then
        return
    end
    if castFrame == _G.DEFAULT_CHAT_FRAME then
        if not details.flashTabOnGeneral then
            return
        end
        -- Popout modes carry the alert on the conversation tab; Blizzard
        -- suppresses the general-tab flash there too.
        if GetCVar("whisperMode") ~= "inline" then
            return
        end
    elseif not details.flashTab then
        return
    end
    -- A conversation window CREATED by this message has no ghost yet; the
    -- queued refresh above builds it and the alert mirror (TabAlerting) in
    -- the refresh starts its flash.
    local g = GhostFor(castFrame)
    if g and g:IsShown() then
        g:StartFlash()
    end
end

-------------------------------------------------------------------------------
--  Passthrough (full hide): our visuals hide; the invisible interaction plane
--  is click-disabled by the sweep (called by the module's passthrough flow).
-------------------------------------------------------------------------------
function CHAT.TabsSetPassthrough(enabled)
    if enabled then
        if tabStrip:IsShown() then
            mod._stripWasShown = true
            tabStrip:Hide()
        end
    else
        if mod._stripWasShown then
            mod._stripWasShown = nil
            tabStrip:Show()
        end
    end
    CHAT.TabsSweepBlizzard()
end

-------------------------------------------------------------------------------
--  Options-contract exports: same names the options page (and the module's
--  own appliers) call. All styling-only now -- geometry belongs to Blizzard.
-------------------------------------------------------------------------------
function CHAT.ApplyTabAppearance()
    RequestRefresh()
end
function CHAT.ApplyTabBorders()
    RequestRefresh()
end
function CHAT.ApplyTabSeparators()
    RequestRefresh()
end
function CHAT.ApplyTabSpacing()
    RequestRefresh()
end

function CHAT.ApplyTabLayout()
    PositionStrip()
    RequestRefresh()
end

function CHAT.ApplyTabPadding()
    PositionStrip()
    if CHAT.ApplyExtendedBackground then
        CHAT.ApplyExtendedBackground()
    end
    if CHAT.ApplySidebarIcons then
        CHAT.ApplySidebarIcons()
    end
    RequestRefresh()
end

-------------------------------------------------------------------------------
--  Init: wired by the module root once panels exist (TabsInit), then kept
--  fresh by the module's existing deferred passes (QueueTabPass/QueueFullPass
--  call TabsRefresh + TabsSweepBlizzard).
-------------------------------------------------------------------------------
function CHAT.TabsInit()
    if CHAT.EngineSetTabObserver then
        CHAT.EngineSetTabObserver(OnTabMessage)
    end
    CHAT.TabsSweepBlizzard()
    RefreshNow()
end
