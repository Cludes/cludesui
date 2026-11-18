if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIChat.lua
--
--  Chat module root: panels, sidebar, fade/visibility, edit box skin, tabs.
--  Message DISPLAY is owned by our own engine (CludesUIChat_Engine.lua):
--  Blizzard's chat frames keep running as the secure formatting/data plane
--  (their visual children are parked in a hidden container), and every
--  formatted line is bridged into a ScrollingMessageFrame we own. Features:
--    - Dark unified background (chat + input as one panel)
--    - Tab restyling (custom fonts, colors, spacing, and borders)
--    - Blizzard chrome removal
--    - Timestamps (showTimestamps CVar, rides Blizzard's secure formatter)
--    - Thin CUI scrollbar on our message frames
--    - Copy Chat button + session history (own message store)
-------------------------------------------------------------------------------
local addonName, mod = ...
if
    not (
        CludesUI
        and CludesUI._ModuleNS
        and CludesUI.NewInternals
        and CludesUI.NewCombatQueue
        and CludesUI.PadGamepadUI
    )
then
    CUI_CLIENT_BLOCKED = true
    return
end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring
CludesUI._ModuleNS[addonName] = mod -- LOD options files read this module ns via the registry
mod.CombatQueue = CludesUI.NewCombatQueue(CreateFrame("Frame"))
local CUI = _G.CludesUI
if not CUI then
    return
end

mod.ECHAT = mod.ECHAT or {}
local CHAT = mod.ECHAT

-- The chat panel hangs off UIParent, placed numerically from the chat frame's rect
-- (PositionChatPanel) so nothing of ours sits in Blizzard's anchor chain. The
-- interaction follower (do-block after SyncChatFrameState) drives repositioning, armed
-- only while chat is interacted with -- NO recurring work at idle.

-- The tab strip is fully owned now (CludesUIChat_Tabs.lua): our buttons on
-- our own container, drawn from the same settings. The old in-place reskin of
-- Blizzard's tabs (host clip, per-tab host trios, seat normalizes) is gone.

-- Chat uses the same tuned Blizzard-border offsets as other rectangular CUI
-- panels. Without this registration the shared engine's lookup resolves to
-- zero, clipping the border texture into the panel.
CUI.RegisterBorderDefaults("chat", {
    ["blizz"] = {
        defaultSize = "heavy",
        sizes = {
            none = { offsetX = 0, offsetY = 0, shiftX = 0, shiftY = 0 },
            thin = { offsetX = 2, offsetY = 1, shiftX = 0, shiftY = 0 },
            normal = { offsetX = 3, offsetY = 2, shiftX = 0, shiftY = 0 },
            heavy = { offsetX = 4, offsetY = 2, shiftX = 1, shiftY = 0 },
            strong = { offsetX = 4, offsetY = 2, shiftX = 2, shiftY = 0 },
        },
    },
})

local min, upper, floor, ceil, abs = min, max, floor, ceil, math.abs

-- Per-frame state lives here, never as properties on Blizzard's chat frame
-- tables (that taints them -> HistoryKeeper errors in protected instances).
local _cfd = {}
local function CFD(castFrame)
    local skinData = _cfd[castFrame]
    if not skinData then
        skinData = {}
        _cfd[castFrame] = skinData
    end
    return skinData
end
CludesUI._chatCFD = CFD

local CHAT_DEFAULTS = {
    profile = {
        chat = {
            enabled = true,
            visibility = "always",
            bgAlpha = 0.65,
            bgR = 0.03,
            bgG = 0.045,
            bgB = 0.05,
            bgTexture = "none", -- chat background texture key (Unit Frames bar texture catalogue)
            timestampFormat = "%I:%M ",
            timestampAll = false,
            font = "__global",
            outlineMode = "__global",
            fontSize = 12,
            tabFont = "__global",
            tabFontSize = 11,
            tabFontColor = { r = 1, g = 1, b = 1, a = 0.65 },
            tabFontColorActive = { r = 1, g = 1, b = 1, a = 1 },
            sidebarVisibility = "always",
            hideBorders = false,
            innerBorderColor = { r = 1, g = 1, b = 1, a = 0.06 },
            innerBorderColorMode = "custom",
            panelBorderBehind = false,
            tabBackgroundTexture = "none",
            activeTabBorder = true,
            tabBorderColorActive = { r = 1, g = 1, b = 1, a = 0.18 },
            -- WoW Forever: tabs inside one continuous chat panel (per-client default).
            extendBgBehindTabs = (CludesUI.IS_FOREVER == true),
            panelBorderTexture = "solid",
            panelBorderThickness = "none",
            panelBorderColorMode = "custom",
            panelBorderColor = { r = 1, g = 1, b = 1 },
            panelBorderOpacity = 0.18,
            tabSpacing = 1,
            tabPadding = 0,
            syncTabBorder = true,
            tabBorderTexture = "solid",
            tabBorderThickness = "none",
            tabBorderColorMode = "custom",
            tabBorderColor = { r = 1, g = 1, b = 1 },
            tabBorderOpacity = 0.18,
            tabHeight = 24,
            tabInnerPaddingX = 12,
            scrollButtonOnChat = false,
            tabBackgroundColor = { r = 0.03, g = 0.045, b = 0.05, a = 0.44 },
            tabBackgroundColorActive = { r = 0.03, g = 0.045, b = 0.05, a = 0.65 },
            activeUnderline = true,
            activeUnderlineColorMode = "accent",
            activeUnderlineColor = { r = 0.05, g = 0.82, b = 0.61, a = 1 },
            showFriends = true,
            showGuild = false,
            showDurability = false,
            showCopy = true,
            showPortals = true,
            showVoice = false,
            showSettings = true,
            showChatMenu = false,
            showScroll = true,
            hideTooltipOnHover = true,
            sidebarRight = false,
            sidebarSeparate = false,
            sidebarSeparateSpacing = 8,
            iconR = 1,
            iconG = 1,
            iconB = 1,
            iconUseAccent = false,
            idleFadeDelay = 15,
            idleFadeStrength = 40,
            idleFadeEnabled = true,
            inputOnTop = false,
            -- Style page (reload-gated): Blizzard Style / Classic WoW UI
            useBlizzardStyle = false,
            useClassicStyle = false,
            -- The WoW Forever look's Border Style (latched in ns.ChatStyle):
            -- "textured" = Slim Textured, the default there (an unset value
            -- reads the same, CludesUI.ForeverBorderKind), "slim" = Slim,
            -- "heavy" = Heavy Bronze. Nil on every other client.
            foreverBorder = (CludesUI.IS_FOREVER == true) and "textured" or nil,
            lockChatSize = false,
            abbreviateChannels = true, -- same key as live: saved settings carry over
            abbreviateChannelLetters = false, -- world channels as letters (Ge, T, LD, WD, LFG) instead of their numbers
            classColorNames = true,
            hideSidebarBg = false,
            sidebarIconScale = 1.0,
            sidebarIconSpacing = 10,
            freeMoveIcons = false,
            iconPositions = {},
            sidebarIconOrder = {
                showCopy = 1,
                showPortals = 2,
                showVoice = 3,
                showSettings = 4,
            },
            -- Session chat history (CludesUIChat_SessionHistory.lua, SavedVariablesPerCharacter)
            persistChatHistory = true,
            persistChatHistoryMaxLines = 100,
        },
    },
}

local _chatDB
local function EnsureDB()
    if _chatDB then
        return _chatDB
    end
    if not CUI.Lite then
        return nil
    end
    _chatDB = CUI.Lite.NewDB("CludesUIChatDB", CHAT_DEFAULTS)
    _G._CUCHAT_DB = _chatDB
    -- One-time migration: mouseover -> always (idle fade replaces it)
    if _chatDB.profile and _chatDB.profile.chat and _chatDB.profile.chat.visibility == "mouseover" then
        _chatDB.profile.chat.visibility = "always"
    end
    return _chatDB
end

function CHAT.DB()
    local skinData = EnsureDB()
    if skinData and skinData.profile and skinData.profile.chat then
        return skinData.profile.chat
    end
    return {
        enabled = true,
        visibility = "always",
        persistChatHistory = true,
        persistChatHistoryMaxLines = 100,
    }
end

-- Style page choice (reload-gated): "cui" | "blizzard" | "classic". Read from
-- the real profile once and latched for the session -- never from ECHAT.DB()'s
-- stand-in table, which would latch "cui" before the DB exists. On ns (the
-- module namespace), where the Style page and the profile switch look it up.
function mod.ChatStyle()
    local val = mod._chatStyle
    if val == nil then
        local skinData = _G._CUCHAT_DB
        local c = skinData and skinData.profile and skinData.profile.chat
        if not c then
            return "cui"
        end
        val = (c.useClassicStyle and "classic") or (c.useBlizzardStyle and "blizzard") or "cui"
        mod._chatStyle = val
        -- The WoW Forever variant of Blizzard Style, latched with it: the
        -- Forever client, Blizzard Style, and the sibling useForeverStyle
        -- flag set together with the Blizzard one (_chatForeverFlag). Unlike
        -- the other modules' Forever latches it also asks for the kit's
        -- frame (CludesUI.ForeverBorderOK): a client that cannot draw it
        -- renders plain Blizzard Style.
        mod._chatForeverFlag = val == "blizzard" and CludesUI.IS_FOREVER == true and c.useForeverStyle == true
        mod._chatForever = mod._chatForeverFlag and CludesUI.ForeverBorderOK()
        -- Its Border Style (Chat page), latched with it: "slim" (the shipped
        -- line), "textured" (Blizzard's live line; unset, the default, reads
        -- the same) or "heavy" (the heavy frame), each kind that lacks its art
        -- drawing Slim (CludesUI.ForeverBorderKind).
        mod._chatFvKind = mod._chatForever and CludesUI.ForeverBorderKind(c.foreverBorder) or nil
    end
    return val
end
-- WoW Forever variant: ChatStyle() still reads "blizzard" (every stock site
-- stays as it is); this gates the Forever-only pieces. False off Forever.
function mod.ChatForever()
    if mod._chatStyle == nil then
        mod.ChatStyle()
    end
    return mod._chatForever == true
end
-- The WoW Forever kit's Border Style this session: "slim", "textured" or
-- "heavy" (latched with the look). Nil everywhere else.
function mod.ChatFvKind()
    if mod._chatStyle == nil then
        mod.ChatStyle()
    end
    return mod._chatFvKind
end
-- The WoW Forever kit wears the heavy bronze frame this session (Border
-- Style Heavy Bronze). False everywhere else.
function mod.ChatFvHeavy()
    return mod.ChatFvKind() == "heavy"
end
-- The variant as the profile flags latched it, frame or not: what a profile
-- flag comparison must read (ChatForever() stays false where the frame
-- cannot be drawn, so comparing it to profile flags would never settle).
function mod.ChatForeverFlag()
    if mod._chatStyle == nil then
        mod.ChatStyle()
    end
    return mod._chatForeverFlag == true
end
-- Profiles (ProfileChangesStyle's `extra`, handed the incoming chat table):
-- true when that profile would latch another Border Style kind than the one
-- latched this session (the latch above, read off `c`), so the switch asks
-- for a reload.
function mod.ChatFvBorderChanged(c)
    local kind
    if
        type(c) == "table"
        and not c.useClassicStyle
        and c.useBlizzardStyle
        and CludesUI.IS_FOREVER == true
        and c.useForeverStyle == true
        and CludesUI.ForeverBorderOK()
    then
        kind = CludesUI.ForeverBorderKind(c.foreverBorder)
    end
    return kind ~= mod.ChatFvKind()
end
-- Both stock styles: Blizzard's own chat frame art and input box are revealed
-- in place (only the suppression is skipped); our panel paint, borders and
-- input chrome stand down. The display engine and every text feature run as
-- in the CludesUI look.
function mod.ChatStock()
    return mod.ChatStyle() ~= "cui"
end
-- Blizzard's own chat frame art and input box revealed: the stock styles
-- minus WoW Forever, which strips them like the CludesUI look and draws
-- its bronze kit on our panel instead (options still gate as Blizzard Style).
function mod.ChatStockArt()
    return mod.ChatStock() and not mod.ChatForever()
end
-- Blizzard Style only: Blizzard's real tab strip is revealed as well. Classic
-- and WoW Forever keep the ghost tabs over the invisible strip, painted with
-- their own tab art.
function mod.ChatBlizzTabs()
    return mod.ChatStyle() == "blizzard" and not mod.ChatForever()
end
-- Stock-aware reads of the CludesUI-only layout settings (the band behind
-- the tabs, input on top, the panel and sidebar borders).
function CHAT.ExtendBgBehindTabs(conf)
    return conf.extendBgBehindTabs == true and not mod.ChatStock()
end
function CHAT.InputOnTop(conf)
    return (conf.inputOnTop and not mod.ChatStock()) and true or false
end
function CHAT.BordersHidden(conf)
    return (conf.hideBorders or mod.ChatStock()) and true or false
end

local Pix = CUI.PP
local function GetFont()
    local conf = CHAT.DB()
    local fontKey = conf.font or "__global"
    if fontKey == "__global" then
        return (CUI.GetFontPath("chat")) or STANDARD_TEXT_FONT
    end
    return (CUI.ResolveFontName(fontKey)) or STANDARD_TEXT_FONT
end

local function GetOutlineFlag()
    local conf = CHAT.DB()
    local mode = conf.outlineMode or "__global"
    if mode == "__global" then
        return (CUI.GetFontOutlineFlag("chat")) or ""
    end
    -- Chat-specific outline override; still slug-gated by "Never Show Slug".
    if mode == "outline" then
        return (CUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG"
    end
    if mode == "thick" then
        return (CUI.SlugFlag("THICKOUTLINE, SLUG")) or "THICKOUTLINE, SLUG"
    end
    return ""
end

-- Published for the tabs and the stock sidebar, which follow the Chat page's own font and
-- outline pickers, not just the global "chat" module font. Going straight to
-- CUI.GetFontPath("chat") skips the cfg.font / cfg.outlineMode overrides above.
CHAT.GetFont = GetFont
CHAT.GetOutlineFlag = GetOutlineFlag

-- Strength 100 is a true full hide: alpha 0 plus mouse passthrough
-- (SetChatMousePassthrough).
local function GetIdleFadeAlpha()
    local conf = CHAT.DB()
    local strength = min(conf.idleFadeStrength or 40, 100)
    return 1 - (strength / 100)
end
local FADE_IN_DURATION = 0.35
local FADE_OUT_DURATION = 1.0
local IDLE_FADE_OUT_DURATION = 2.0
local _chatAlphaCurrent = 1
local _chatFadeFrame = CreateFrame("Frame")
_chatFadeFrame:Hide()
-- Tab fade rides the strip: our tab buttons are children of our own strip
-- container, which _ApplyAlpha fades directly. The old constraints on
-- Blizzard's tabs still stand for anyone tempted to touch the HIDDEN strip:
-- NEVER write the six CHAT_FRAME_TAB_*_ALPHA globals (an addon-written global
-- taints, Blizzard reads those constants inside its dock-update/temp-window
-- chains, and the tainted execution hits secret whisper values -- no
-- timing/deferral fix exists) and never fight FCFTab_UpdateAlpha.

-- Tab strip height (the owned strip in CludesUIChat_Tabs.lua). Used by
-- "Extend Background Behind Tabs" to size the strip behind the tabs and shift
-- the sidebar icon chain up by the same amount.
local TAB_STRIP_H = 24
local function GetTabHeight()
    local conf = CHAT.DB()
    return conf.tabHeight or TAB_STRIP_H
end

local function GetTabPadding()
    local conf = CHAT.DB()
    if CHAT.ExtendBgBehindTabs(conf) then
        return 0
    end
    return conf.tabPadding or 0
end
local function GetTabAreaHeight()
    return GetTabHeight() + GetTabPadding()
end

-- Set<Name> for the locals this file shares with the CUI_Chat_*.lua files
-- (the background colour here, the sidebar fade state further down). Every
-- file that reads one keeps a copy, so a write goes through these; they are
-- assigned at the end of this file, next to ns._internals.
local SetBgR, SetBgG, SetBgB, SetBgA
local SetSidebarLayoutVisible, SetSidebarFadeFrame
local SetSidebarFadeTarget, SetSidebarFadeAlpha
local BG_R, BG_G, BG_B, BG_A = 0.03, 0.045, 0.05, 0.70

local EDIT_BG_R, EDIT_BG_G, EDIT_BG_B = 0.05, 0.065, 0.08

local function GetInnerBorderColor(conf)
    if conf.innerBorderColorMode == "accent" and CludesUI.GetAccentColor then
        local region, g, b = CludesUI.GetAccentColor()
        local c = conf.innerBorderColor
        return region, g, b, (c and c.a) or 0.06
    end
    local c = conf.innerBorderColor or { r = 1, g = 1, b = 1, a = 0.06 }
    return c.r or 1, c.g or 1, c.b or 1, c.a == nil and 0.06 or c.a
end

-- Chat frame text size is Blizzard's per-frame setting (right-click tab ->
-- Font Size); the CUI profile mirrors the latest user-selected value.
local function GetFrameFontSize(ident)
    if FCF_GetChatWindowInfo then
        local _, fontSize = FCF_GetChatWindowInfo(ident)
        if fontSize and fontSize > 0 then
            return fontSize
        end
    end
    return 12
end

local function GetEditBoxHeight()
    return min(60, upper(10, CHAT.DB().editBoxHeight or 23))
end
local function GetEditBoxFont()
    local key = CHAT.DB().editBoxFont
    if not key or key == "__chat" then
        return GetFont()
    end
    if key == "__global" then
        return (CUI.GetFontPath("chat")) or STANDARD_TEXT_FONT
    end
    return (CUI.ResolveFontName(key)) or GetFont()
end
local function GetEditBoxFontSize(ident)
    return CHAT.DB().editBoxFontSize or GetFrameFontSize(ident)
end
-- Tab font size is hardcoded to 11 (no getter).

-- Chat background texture catalogue: same set as the Unit Frames bar texture
-- dropdown (same shared media files), with SharedMedia statusbar textures
-- appended through the shared CludesUI helper.
mod.chatBgTextures, mod.chatBgTextureNames, mod.chatBgTextureOrder = CludesUI.BuildBarTextureTables(true)

-- Refresh from SharedMedia (idempotent; registers the late-registration
-- callback on first call, same as the other modules).
function CHAT.RefreshBgTextureCatalogue()
    CludesUI.AppendSharedMediaTextures(
        mod.chatBgTextureNames,
        mod.chatBgTextureOrder,
        nil,
        mod.chatBgTextures
    )
end

-- Apply background settings from DB to all skinned chat frames
function CHAT.ApplyBackground()
    local p = CHAT.DB()
    SetBgR(p.bgR or 0.03)
    SetBgG(p.bgG or 0.045)
    SetBgB(p.bgB or 0.05)
    SetBgA(p.bgAlpha or 0.65)

    -- "none" = solid color instead of a texture
    local texKey = p.bgTexture or "none"
    local texPath
    if texKey ~= "none" then
        CHAT.RefreshBgTextureCatalogue()
        if CludesUI.ResolveTexturePath then
            texPath = CludesUI.ResolveTexturePath(mod.chatBgTextures, texKey, nil)
        else
            texPath = mod.chatBgTextures[texKey]
        end
    end

    -- Stock styles: Blizzard's own chat background shows through (revealed on
    -- the chat frame itself), so our panel and sidebar carry no paint.
    local stock = mod.ChatStock()
    for index = 1, 20 do
        local castFrame = _G["ChatFrame" .. index]
        if castFrame and CFD(castFrame).bg then
            local bgTex = CFD(castFrame).bg:GetRegions()
            if bgTex then
                if stock and bgTex.SetColorTexture then
                    if bgTex.SetVertexColor then
                        bgTex:SetVertexColor(1, 1, 1, 1)
                    end
                    bgTex:SetColorTexture(0, 0, 0, 0)
                elseif texPath and bgTex.SetTexture then
                    bgTex:SetTexture(texPath)
                    bgTex:SetVertexColor(BG_R, BG_G, BG_B, BG_A)
                elseif bgTex.SetColorTexture then
                    -- Clear the texture-mode tint before returning to solid, or
                    -- the color double-tints through the vertex color.
                    if bgTex.SetVertexColor then
                        bgTex:SetVertexColor(1, 1, 1, 1)
                    end
                    bgTex:SetColorTexture(BG_R, BG_G, BG_B, BG_A)
                end
            end
        end
    end
    -- WoW Forever: the colour and texture fill the kit's framed boxes instead.
    if mod.ChatForever() then
        CHAT.FV_PaintFills(texPath, BG_R, BG_G, BG_B, BG_A)
    end
    local cf1 = _G.ChatFrame1
    if cf1 and CFD(cf1).sidebar then
        local sbBg = CFD(cf1).sidebar:GetRegions()
        if sbBg and sbBg.SetColorTexture then
            sbBg:SetColorTexture(BG_R, BG_G, BG_B, stock and 0 or BG_A)
        end
        -- Blizzard Style column backdrop: the window colour, re-read.
        if CHAT.SB_SyncBackdrop then
            CHAT.SB_SyncBackdrop(true)
        end
    end
    -- Keep the behind-tabs extension in sync with the new color/opacity.
    if CHAT.ApplyExtendedBackground then
        CHAT.ApplyExtendedBackground()
    end
    if CHAT.ApplyTabAppearance then
        CHAT.ApplyTabAppearance()
    end
end

-- Mouseover sidebars only participate in panel geometry while visible; kept
-- separate from alpha so the border expands on hover and contracts only once
-- the fade-out has completed.
local _sidebarMouseoverLayoutVisible = false
local function SidebarParticipatesInLayout(conf)
    local mode = conf.sidebarVisibility or "always"
    return mode == "always" or (mode == "mouseover" and _sidebarMouseoverLayoutVisible)
end

-- Extend the chat background up behind the tab strip (and the sidebar by the same
-- amount) so the tabs sit on one continuous panel. Opt-in via cfg.extendBgBehindTabs
-- (default off, reload on toggle). Creates OUR OWN frames only -- never touches a
-- Blizzard tab or GeneralDockManager -- so it is taint free; strip height matches the
-- dock height for pixel alignment. The strip is ONE frame parented to UIParent (not a
-- chat frame), pinned to ChatFrame1's bg top: UIParent parenting keeps it visible when
-- switching docked tabs (a per-frame child would vanish with its hidden frame), and
-- BACKGROUND strata keeps it behind the tabs. It does not inherit a chat frame's alpha,
-- so _ApplyAlpha fades it directly.
function CHAT.ApplyExtendedBackground()
    local conf = CHAT.DB()
    local extend = CHAT.ExtendBgBehindTabs(conf)
    local cf1 = _G.ChatFrame1
    local d1 = cf1 and CFD(cf1)
    local bg1 = d1 and d1.bg
    if not bg1 then
        return
    end

    local ext = mod._chatBgExt
    if extend and not ext then
        ext = CreateFrame("Frame", nil, UIParent)
        ext:SetPoint("BOTTOMLEFT", bg1, "TOPLEFT", 0, 0)
        ext:SetPoint("BOTTOMRIGHT", bg1, "TOPRIGHT", 0, 0)
        ext:SetHeight(GetTabAreaHeight())
        local t = ext:CreateTexture(nil, "BACKGROUND")
        t._cuiOwned = true
        t:SetAllPoints()
        mod._chatBgExt = ext
        mod._chatBgExtTex = t
    end
    if ext then
        ext:SetHeight(GetTabAreaHeight())
        if mod._chatBgExtTex then
            mod._chatBgExtTex:SetColorTexture(BG_R, BG_G, BG_B, BG_A)
        end
        -- BACKGROUND strata (still above the 3D world) puts tabs in front;
        -- the strip never overlaps chat text or the sidebar.
        ext:SetFrameStrata("BACKGROUND")
        -- Level 1 leaves level 0 free for the panel border's "Show Behind"
        -- mode, whose outward half stays visible around the strip.
        ext:SetFrameLevel(1)
        if _chatAlphaCurrent then
            ext:SetAlpha(_chatAlphaCurrent)
        end
        ext:SetShown(extend)
    end

    -- Sidebar (ChatFrame1 only): matching strip plus a 1px divider so the
    -- sidebar/chat hairline runs full height. Can be the sidebar's own child
    -- (rendered behind icons via its own frame level) since the sidebar is
    -- always visible and fades on its own.
    local scrollBar = d1.sidebar
    if scrollBar then
        local showSb = extend and not conf.hideSidebarBg
        local sext = d1.sidebarExt
        if showSb and not sext then
            sext = CreateFrame("Frame", nil, scrollBar)
            sext:SetPoint("BOTTOMLEFT", scrollBar, "TOPLEFT", 0, 0)
            sext:SetPoint("BOTTOMRIGHT", scrollBar, "TOPRIGHT", 0, 0)
            sext:SetHeight(GetTabAreaHeight())
            sext:SetFrameLevel(scrollBar:GetFrameLevel())
            local t = sext:CreateTexture(nil, "BACKGROUND")
            t._cuiOwned = true
            t:SetAllPoints()
            local div = sext:CreateTexture(nil, "OVERLAY", nil, 7)
            div._cuiOwned = true
            div:SetWidth((Pix and Pix.mult) or 1)
            div:SetColorTexture(GetInnerBorderColor(conf))
            if Pix and Pix.DisablePixelSnap then
                Pix.DisablePixelSnap(div)
            end
            d1.sidebarExt = sext
            d1.sidebarExtTex = t
            d1.sidebarExtDiv = div
        end
        if sext then
            sext:SetHeight(GetTabAreaHeight())
            if d1.sidebarExtTex then
                d1.sidebarExtTex:SetColorTexture(BG_R, BG_G, BG_B, BG_A)
            end
            local div = d1.sidebarExtDiv
            if div then
                div:SetColorTexture(GetInnerBorderColor(conf))
                div:ClearAllPoints()
                if conf.sidebarRight then
                    div:SetPoint("TOPLEFT", sext, "TOPLEFT", 0, 0)
                    div:SetPoint("BOTTOMLEFT", sext, "BOTTOMLEFT", 0, 0)
                else
                    div:SetPoint("TOPRIGHT", sext, "TOPRIGHT", 0, 0)
                    div:SetPoint("BOTTOMRIGHT", sext, "BOTTOMRIGHT", 0, 0)
                end
                div:SetShown(not conf.hideBorders)
            end
            sext:SetShown(showSb)
        end
    end

    -- One border around the complete extended panel: tab strip, chat
    -- background, and the sidebar on whichever side it currently occupies.
    local border = mod._chatPanelBorder
    if not border then
        border = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        border:EnableMouse(false)
        mod._chatPanelBorder = border
    end
    if border and mod.ChatStock() then
        -- Stock styles: Blizzard's own chat frame border is the border.
        border:Hide()
        if mod._sidebarSeparateBorder then
            mod._sidebarSeparateBorder:Hide()
        end
    elseif border then
        border:ClearAllPoints()
        local includeSidebar = scrollBar
            and not conf.hideSidebarBg
            and SidebarParticipatesInLayout(conf)
            -- A separate sidebar is its own island: excluded here, wrapped
            -- by its own border below.
            and conf.sidebarSeparate ~= true
        local topExtension = extend and GetTabAreaHeight() or 0
        if includeSidebar and not conf.sidebarRight then
            border:SetPoint("TOPLEFT", scrollBar, "TOPLEFT", 0, topExtension)
            border:SetPoint("BOTTOMRIGHT", bg1, "BOTTOMRIGHT", 0, 0)
        elseif includeSidebar and conf.sidebarRight then
            border:SetPoint("TOPLEFT", bg1, "TOPLEFT", 0, topExtension)
            border:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMRIGHT", 0, 0)
        else
            border:SetPoint("TOPLEFT", bg1, "TOPLEFT", 0, topExtension)
            border:SetPoint("BOTTOMRIGHT", bg1, "BOTTOMRIGHT", 0, 0)
        end
        -- Chat tabs/edit box can live on a higher strata than the chat frame,
        -- so a frame-level bump alone is not enough. "Show Behind" drops the
        -- border to the very back instead, so the chat fill covers its inward
        -- half and only the outward half frames the panel.
        local showBehind = conf.panelBorderBehind == true
        border:SetFrameStrata(showBehind and "BACKGROUND" or "MEDIUM")
        -- Solid borders use a child at host+1; textured borders render at host
        -- level. Behind mode keeps both at 0, under the extended strip (level 1)
        -- and chat bg. Capped below 100: per-tab border hosts sit at level 100
        -- and must draw over the chat border.
        local borderLevel = showBehind and 0 or upper(96, min(98, cf1:GetFrameLevel() + 20))
        border:SetFrameLevel(borderLevel)

        if CludesUI.ApplyBorderStyle then
            local sizes = { none = 0, thin = 1, normal = 2, heavy = 3, strong = 4 }
            local thicknessKey = conf.panelBorderThickness or "none"
            local mode = conf.panelBorderColorMode or "custom"
            local color
            if mode == "accent" then
                local region, g, b = CludesUI.GetAccentColor()
                color = { r = region, g = g, b = b }
            elseif mode == "class" then
                local _, class = UnitClass("player")
                color = class and RAID_CLASS_COLORS[class] or { r = 1, g = 1, b = 1 }
            else
                color = conf.panelBorderColor or { r = 1, g = 1, b = 1 }
            end
            local alpha = conf.panelBorderOpacity
            if alpha == nil then
                alpha = mode == "custom" and 0.18 or 0.5
            end
            local bSize = sizes[thicknessKey] or 1
            local bTex = conf.panelBorderTexture or "solid"
            -- Exact pixel size beside the step (nil = the legacy step path).
            local bPx = CludesUI.BorderPx(conf.panelBorderThicknessPx, bSize, bTex)
            CludesUI.ApplyBorderStyle(
                border,
                bSize,
                color.r,
                color.g,
                color.b,
                alpha,
                bTex,
                conf.panelBorderOffsetX,
                conf.panelBorderOffsetY,
                conf.panelBorderShiftX,
                conf.panelBorderShiftY,
                "chat",
                thicknessKey,
                nil,
                bPx
            )
            local solidBorder = Pix and Pix.GetBorders and Pix.GetBorders(border)
            if solidBorder then
                solidBorder:SetFrameLevel(borderLevel + (showBehind and 0 or 1))
            end
            border:Show()

            -- Separate Sidebar: its own border, same style and construction class as
            -- the panel border (our UIParent frame anchored to our sidebar frame).
            local wantSbBorder = conf.sidebarSeparate == true
                and scrollBar
                and not conf.hideSidebarBg
                and (conf.sidebarVisibility or "always") ~= "never"
            local sbBorder = mod._sidebarSeparateBorder
            if wantSbBorder and not sbBorder then
                sbBorder = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
                sbBorder:EnableMouse(false)
                mod._sidebarSeparateBorder = sbBorder
            end
            if sbBorder then
                if wantSbBorder then
                    local sbTop = (extend and not conf.hideSidebarBg) and GetTabAreaHeight() or 0
                    sbBorder:ClearAllPoints()
                    sbBorder:SetPoint("TOPLEFT", scrollBar, "TOPLEFT", 0, sbTop)
                    sbBorder:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMRIGHT", 0, 0)
                    sbBorder:SetFrameStrata(showBehind and "BACKGROUND" or "MEDIUM")
                    sbBorder:SetFrameLevel(borderLevel)
                    CludesUI.ApplyBorderStyle(
                        sbBorder,
                        bSize,
                        color.r,
                        color.g,
                        color.b,
                        alpha,
                        bTex,
                        conf.panelBorderOffsetX,
                        conf.panelBorderOffsetY,
                        conf.panelBorderShiftX,
                        conf.panelBorderShiftY,
                        "chat",
                        thicknessKey,
                        nil,
                        bPx
                    )
                    local sbSolid = Pix and Pix.GetBorders and Pix.GetBorders(sbBorder)
                    if sbSolid then
                        sbSolid:SetFrameLevel(borderLevel + (showBehind and 0 or 1))
                    end
                    sbBorder:Show()
                else
                    sbBorder:Hide()
                end
            end
        else
            CludesUI.ApplyBorderStyle(border, 0, 1, 1, 1, 0, conf.panelBorderTexture or "solid")
            border:Hide()
        end
    end
    if CHAT.ApplyTabBorders then
        CHAT.ApplyTabBorders()
    end
    if CHAT.ApplyTabSeparators then
        CHAT.ApplyTabSeparators()
    end
    if CHAT.ApplyTabAppearance then
        CHAT.ApplyTabAppearance()
    end
end

-- Re-apply font to all chat text surfaces. Chat text size is Blizzard's
-- per-frame setting (right-click tab -> Font Size; we only set family +
-- outline). The Blizzard frames keep receiving the font too: the hosted
-- combat log renders through ChatFrame2, and their buffers should wrap
-- identically to ours for backfill copies.
function CHAT.ApplyFonts()
    local font = GetFont()
    local editFont = GetEditBoxFont()
    local outline = GetOutlineFlag()
    for index = 1, 20 do
        local castFrame = _G["ChatFrame" .. index]
        if castFrame and castFrame.SetFont then
            local size = GetFrameFontSize(index)
            -- Same per-window font FAMILY as our display view (CJK members):
            -- the invisible Blizzard frame owns hyperlink hit-zones, so its
            -- glyph metrics must match ours on lines carrying CJK text.
            local fam = CHAT.EngineFontFamily and CHAT.EngineFontFamily(index, font, size, outline)
            if fam then
                castFrame:SetFontObject(fam)
            else
                castFrame:SetFont(font, size, outline)
            end
        end
        local eb = _G["ChatFrame" .. index .. "EditBox"]
        if eb then
            local size = GetEditBoxFontSize(index)
            eb:SetFont(editFont, size, outline)
            if index <= 10 then
                if eb.header then
                    eb.header:SetFont(editFont, size, outline)
                end
                if eb.headerSuffix then
                    eb.headerSuffix:SetFont(editFont, size, outline)
                end
            end
        end
    end
    -- Our message frames (family/outline ours, size per window from Blizzard).
    if CHAT.EngineApplyFonts then
        CHAT.EngineApplyFonts()
    end
end

-- One size for every chat window (the options slider). Persistence rides
-- Blizzard's own per-window storage -- SetChatWindowSize is a plain C write.
-- The CUI profile mirrors the latest size selected either here or through a
-- chat tab's right-click menu, so the native menu choice survives reload.
-- NEVER route
-- this through FCF_SetChatWindowFontSize: the old in-place skin's size
-- control rippled through Blizzard's tab-resize/dock machinery measuring
-- secret label widths under our taint (the v7.15-era removal). Under the
-- engine, size only touches storage, SetFont, and OUR frames.
function CHAT.ApplyChatFontSize(size)
    if type(size) ~= "number" or size <= 0 then
        return
    end
    for index = 1, 10 do
        if _G["ChatFrame" .. index] then
            CludesUI.SetChatWindowSize(index, size)
        end
    end
    -- Temp whisper frames carry no numbered storage; their live font is the
    -- state FCF_GetChatWindowInfo reads back, so set it directly.
    local frameList = _G.CHAT_FRAMES
    if type(frameList) == "table" then
        for index = 11, #frameList do
            local castFrame = _G[frameList[index]]
            if castFrame and castFrame.isTemporary and castFrame.inUse and castFrame.SetFont then
                local font, _, flags = castFrame:GetFont()
                if font then
                    castFrame:SetFont(font, size, flags or "")
                end
            end
        end
    end
    CHAT.ApplyFonts()
end

-- Profile-wide font size: cfg.chatFontSize (NO static default -- absence
-- means "not yet captured") is the source of truth; Blizzard's per-window
-- storage stays the delivery vehicle via ApplyChatFontSize, so the taint
-- posture is unchanged. Genesis: seeded from the FIRST character's live
-- size at the first settled sight (pixel-invisible on that character); every
-- later login re-asserts the profile value across windows. The interaction
-- follower mirrors native tab-menu changes because that menu writes the
-- frame font directly without emitting UPDATE_CHAT_WINDOWS.
function CHAT.SyncChatFontSize()
    local conf = CHAT.DB()
    if not conf then
        return
    end
    if conf.chatFontSize == nil then
        local castFrame = _G.ChatFrame1
        if castFrame and castFrame.GetFont then
            local _, fh = castFrame:GetFont()
            if type(fh) == "number" and fh > 0 then
                conf.chatFontSize = math.floor(fh + 0.5)
            end
        end
        return -- live sizes already match what was just captured
    end
    CHAT.ApplyChatFontSize(conf.chatFontSize)
end

-- Class-colored names in message BODIES only: the engine's display
-- transform colors group/raid member names found in the text of Say/Yell/
-- Party/Raid lines, on our display copy. SENDER prefixes are deliberately
-- untouched -- their class coloring is Blizzard default behavior and this
-- module never writes the per-type storage (SetChatColorNameByClass) in
-- either direction.
function CHAT.ApplyClassColorNames(on)
    if CHAT.EngineSetClassColorNames then
        CHAT.EngineSetClassColorNames(on == true)
    end
end

-- Sidebar visibility: always, mouseover, never
local _sidebarFadeTarget = 1
local _sidebarFadeAlpha = 1
local _sidebarFadeFrame

function CHAT.ApplySidebarVisibility()
    local conf = CHAT.DB()
    local mode = conf.sidebarVisibility or "always"
    local cf1 = _G.ChatFrame1
    local sidebar = cf1 and CFD(cf1).sidebar
    if not sidebar then
        return
    end

    if mode == "never" then
        SetSidebarLayoutVisible(false)
        SetSidebarFadeTarget(0)
        SetSidebarFadeAlpha(0)
        sidebar:SetAlpha(0)
        sidebar:EnableMouse(false)
    elseif mode == "mouseover" then
        SetSidebarLayoutVisible(false)
        SetSidebarFadeTarget(0)
        SetSidebarFadeAlpha(0)
        sidebar:SetAlpha(0)
        sidebar:EnableMouse(true)
    else
        SetSidebarLayoutVisible(true)
        SetSidebarFadeTarget(1)
        SetSidebarFadeAlpha(1)
        sidebar:SetAlpha(1)
        sidebar:EnableMouse(true)
    end
    -- Separate-mode border mirrors the sidebar's alpha.
    if mod._sidebarSeparateBorder then
        mod._sidebarSeparateBorder:SetAlpha(_sidebarFadeAlpha)
    end
    -- The fade's cached sidebar mode follows the new visibility (declared
    -- in CUI_Chat_Visibility.lua, hence the runtime lookup).
    if CHAT.InvalidateAlphaCache then
        CHAT.InvalidateAlphaCache()
    end

    -- Re-anchor the extended panel border as the sidebar enters/leaves layout.
    if CHAT.ApplyTabPadding then
        CHAT.ApplyTabPadding()
    elseif CHAT.ApplyExtendedBackground then
        CHAT.ApplyExtendedBackground()
    end

    if not _sidebarFadeFrame then
        SetSidebarFadeFrame(CreateFrame("Frame"))
        _sidebarFadeFrame:Hide()
        _sidebarFadeFrame:SetScript("OnUpdate", function(self, dt)
            local step = dt * 4 -- 0.25s fade
            if _sidebarFadeTarget > _sidebarFadeAlpha then
                SetSidebarFadeAlpha(min(_sidebarFadeTarget, _sidebarFadeAlpha + step))
            else
                SetSidebarFadeAlpha(upper(_sidebarFadeTarget, _sidebarFadeAlpha - step))
            end
            local scrollBar = _G.ChatFrame1 and CFD(_G.ChatFrame1).sidebar
            if scrollBar then
                scrollBar:SetAlpha(min(_sidebarFadeAlpha, _chatAlphaCurrent))
            end
            if mod._sidebarSeparateBorder then
                mod._sidebarSeparateBorder:SetAlpha(min(_sidebarFadeAlpha, _chatAlphaCurrent))
            end
            if _sidebarFadeAlpha == _sidebarFadeTarget then
                self:Hide()
                if _sidebarFadeTarget == 0 and _sidebarMouseoverLayoutVisible then
                    SetSidebarLayoutVisible(false)
                    if CHAT.ApplyTabPadding then
                        CHAT.ApplyTabPadding()
                    elseif CHAT.ApplyExtendedBackground then
                        CHAT.ApplyExtendedBackground()
                    end
                end
            end
        end)
    end
end

-- Show/hide all borders and dividers
function CHAT.ApplyBorders()
    local conf = CHAT.DB()
    local hide = CHAT.BordersHidden(conf)
    local region, g, b, a = GetInnerBorderColor(conf)

    for index = 1, 20 do
        local castFrame = _G["ChatFrame" .. index]
        if castFrame and CFD(castFrame).bg and Pix.GetBorders(CFD(castFrame).bg) then
            Pix.SetBorderColor(CFD(castFrame).bg, region, g, b, a)
            Pix.GetBorders(CFD(castFrame).bg):SetShown(not hide)
        end
        if castFrame and CFD(castFrame).inputDiv then
            CFD(castFrame).inputDiv:SetColorTexture(region, g, b, a)
            -- Input-on-top: the divider marks the overlaid input's edge, so it
            -- shares that input's shown state (ECHAT.ApplyInputTopStrip) --
            -- otherwise it cuts across a message once the strip is released.
            CFD(castFrame).inputDiv:SetShown(
                not hide and (not CHAT.InputOnTop(conf) or CHAT.InputTopStripActive(castFrame))
            )
        end
    end
    local cf1 = _G.ChatFrame1
    if cf1 and CFD(cf1).sidebar then
        local sbBgHidden = conf.hideSidebarBg
        if Pix.GetBorders(CFD(cf1).sidebar) then
            Pix.SetBorderColor(CFD(cf1).sidebar, region, g, b, a)
            Pix.GetBorders(CFD(cf1).sidebar):SetShown(not hide and not sbBgHidden)
        end
        if CFD(cf1).sidebarDiv then
            CFD(cf1).sidebarDiv:SetColorTexture(region, g, b, a)
            CFD(cf1).sidebarDiv:SetShown(not hide)
        end
    end
    -- Mirror border visibility onto the behind-tabs divider continuation.
    if CHAT.ApplyExtendedBackground then
        CHAT.ApplyExtendedBackground()
    end
    if CHAT.ApplyTabSeparators then
        CHAT.ApplyTabSeparators()
    end
end

-- Sidebar hints use the fully skinned GameTooltip when the BlizzardSkin
-- module's tooltip reskin is active; otherwise the lightweight CUI widget
-- tooltip, so Chat has no hard dependency on that module.
local function ShowSidebarIconTooltip(ownerFrame, labelText)
    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("CludesUIBlizzardSkin")
    local useGameTooltip = isLoaded and (not CludesUIDB or CludesUIDB.customTooltips ~= false) and GameTooltip
    ownerFrame._cuiSidebarUsesGameTooltip = useGameTooltip and true or false
    if useGameTooltip then
        GameTooltip:SetOwner(ownerFrame, "ANCHOR_RIGHT")
        GameTooltip:SetText(CUI.L(labelText), 1, 1, 1)
        GameTooltip:Show()
    elseif CUI.ShowWidgetTooltip then
        CUI.ShowWidgetTooltip(ownerFrame, labelText)
    end
end

local function HideSidebarIconTooltip(ownerFrame)
    if ownerFrame and ownerFrame._cuiSidebarUsesGameTooltip then
        GameTooltip:Hide()
        ownerFrame._cuiSidebarUsesGameTooltip = false
    elseif CUI.HideWidgetTooltip then
        CUI.HideWidgetTooltip()
    end
end

-- Numeric placement of the chat panel background. NEVER anchor the panel to the chat
-- frame/edit box: that puts an insecure frame inside ChatFrame1's rect chain, so any
-- layout write of ours (SetPoint, SetShown, even Hide) dirties it, and Blizzard's next
-- temp-window dock resolves geometry THROUGH our anchors, runs tainted, and its
-- FCF_SetLocked write poisons ChatFrame.isLocked. Reading the rect is safe, anchoring
-- is not -- position numerically against UIParent instead.
--
-- The whole pass, reads included, is DEFERRED ONE FRAME: a fresh temp window skins
-- mid-open, and if our first SetPoint lands while the dock is still dirty, that
-- insecure write gets resolved inside Blizzard's own deferred dock pass and taints
-- its isLocked/dock-selected writes. Deferring one tick moves us outside that pass.
-- Do NOT "optimise" by testing the rect synchronously and deferring only writes:
-- GetLeft/Top/ Right/Bottom, GetEffectiveScale, and IsShown all force the layout
-- engine to RESOLVE the frame, which taints exactly like writing does. Dedupe caps
-- this to one queued placement per chat frame per frame; the closure is built once
-- and reused, so repeats cost only the timer.
function CHAT.PositionChatPanel(castFrame)
    local skinData = CFD(castFrame)
    if skinData._posQueued then
        return
    end
    skinData._posQueued = true
    local func = skinData._posDefer
    if not func then
        func = function()
            skinData._posQueued = nil
            CHAT._PositionChatPanelNow(castFrame)
        end
        skinData._posDefer = func
    end
    C_Timer.After(0, func)
end

function CHAT._PositionChatPanelNow(castFrame)
    local skinData = CFD(castFrame)
    local backdrop = skinData and skinData.bg
    if not backdrop then
        return
    end
    -- ChatFrame1's panel keeps tracking even while the frame is dock-hidden
    -- (a selected temp window hides it): the sidebar, the extended tab band,
    -- and the strip visuals all anchor to THIS panel, and skipping it while
    -- hidden strands them when chat is moved. Hidden frames keep live rects.
    if not castFrame:IsShown() and castFrame ~= _G.ChatFrame1 then
        return
    end
    local l, t, region, callback = castFrame:GetLeft(), castFrame:GetTop(), castFrame:GetRight(), castFrame:GetBottom()
    if not (l and t and region and callback) then
        -- Undock rescue: dragging a tab off the dock can end with Blizzard's
        -- StopMovingOrSizing clearing the frame's anchors and never baking the
        -- drop position back on (12.1). The point-less frame then crashes
        -- FCF_SavePositionAndDimensions every frame (GetLeft nil) and renders
        -- nowhere. A shown, undocked chat frame with zero points is only ever
        -- that broken state: re-anchor it at the cursor (the drop spot) so the
        -- next drag-stop iteration saves cleanly and the window stays where
        -- the user dropped it. Costs nothing when healthy -- this branch is
        -- the existing nil-rect early-out.
        if
            castFrame ~= _G.ChatFrame1
            and not castFrame.isDocked
            and castFrame:IsShown()
            and castFrame:GetNumPoints() == 0
        then
            local cx, cy = GetCursorPosition()
            local es = castFrame:GetEffectiveScale()
            local issec = _G.issecretvalue
            if cx and cy and es and es > 0 and not (issec and (issec(cx) or issec(cy))) then
                pcall(function()
                    castFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / es, cy / es)
                end)
            else
                pcall(function()
                    castFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
                end)
            end
        end
        return
    end
    -- Secret-gated like every other per-tick rect read (grip doctrine): a
    -- mid-drag or restricted-content rect must never reach the arithmetic
    -- below at follower cadence. A frame riding StartMoving's hardware
    -- capture reads secret for its whole drag (12.1), so instead of freezing
    -- the panel until the drop, follow by cursor delta from the last healthy
    -- corners -- no secret value is ever read, and the panel+text ride the
    -- drag like the Blizzard-owned art does.
    local issecret = _G.issecretvalue
    if issecret and (issecret(l) or issecret(t) or issecret(region) or issecret(callback)) then
        if _G.MOVING_CHATFRAME == castFrame and skinData._bgL then
            local mx, my = GetCursorPosition()
            if mx and my and not (issecret(mx) or issecret(my)) then
                local ui2 = UIParent:GetEffectiveScale()
                if ui2 and ui2 > 0 then
                    mx, my = mx / ui2, my / ui2
                    local base = skinData._dragCursorBase
                    if not base then
                        base = { x = mx, y = my, l = skinData._bgL, t = skinData._bgT, r = skinData._bgR, b = skinData._bgB }
                        skinData._dragCursorBase = base
                    end
                    local dx, dy = mx - base.x, my - base.y
                    skinData._bgL, skinData._bgT = base.l + dx, base.t + dy
                    skinData._bgR, skinData._bgB = base.r + dx, base.b + dy
                    backdrop:ClearAllPoints()
                    backdrop:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", skinData._bgL, skinData._bgT)
                    backdrop:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", skinData._bgR, skinData._bgB)
                end
            end
        end
        return
    end
    skinData._dragCursorBase = nil
    -- Rest-rect cache (frame-local space) for the tab-drag ownership lane:
    -- the broken StartMoving capture scrambles the rect before any post-hook
    -- can read it, so drag-start grab offsets come from here instead.
    skinData._cfL, skinData._cfT = l, t
    skinData._cfWasDocked = castFrame.isDocked and true or nil
    -- Rects come back in each frame's own space; convert to UIParent's.
    local ui = UIParent:GetEffectiveScale()
    if not ui or ui == 0 then
        return
    end
    local cs = castFrame:GetEffectiveScale() / ui
    -- Insets from ApplyInputPosition (input above/below, its height); falls
    -- back to creation-time geometry before that has ever run.
    local ins = skinData._bgIns
    local il, ir, it, ib
    if ins then
        il, ir, it, ib = ins.l, ins.r, ins.t, ins.b
    else
        il, ir, it, ib = -10, 5, 3, -6
    end
    local leftX, topY = (l * cs) + il, (t * cs) + it
    local right, bottom = (region * cs) + ir, (callback * cs) + ib
    if right - leftX < 1 or topY - bottom < 1 then
        return
    end
    local pl, pt, pr, pb = skinData._bgL, skinData._bgT, skinData._bgR, skinData._bgB
    -- Write only when it moved: this runs every frame and a redundant SetPoint
    -- is still a layout write.
    if
        pl
        and math.abs(pl - leftX) < 0.05
        and math.abs(pt - topY) < 0.05
        and math.abs(pr - right) < 0.05
        and math.abs(pb - bottom) < 0.05
    then
        return
    end
    skinData._bgL, skinData._bgT, skinData._bgR, skinData._bgB = leftX, topY, right, bottom
    backdrop:ClearAllPoints()
    backdrop:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", leftX, topY)
    backdrop:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", right, bottom)
end

-- Direct (no-timer) placement of every panel plus the dock manager. Callable
-- ONLY from OUR OWN execution (interaction follower's OnUpdate, deferred
-- event passes -- both timer-equivalent contexts). Skin-pass call sites keep
-- using the queued PositionChatPanel above.
function CHAT.PositionChatPanelsNow()
    for index = 1, 20 do
        local castFrame = _G["ChatFrame" .. index]
        -- Gate on the panel existing, NOT on _skinned: that table is a local of
        -- CUI_Chat_EditBox.lua, so referencing it here reads a nil GLOBAL.
        if castFrame and CFD(castFrame).bg then
            CHAT._PositionChatPanelNow(castFrame)
        end
    end
    -- The owned tab strip is anchored to the panel and follows for free.
end

-- Panel hosting. Blizzard's house editor is a full-screen UI panel: it hides
-- UIParent and FCF_SetFullScreenFrame reparents the chat frames onto itself so
-- chat stays readable while decorating. That helper only moves widgets whose
-- parent is still UIParent, and our panel frames are UIParent children by design
-- (see the bg creation note), so they stay behind on the hidden UIParent and the
-- entire visible chat -- background, our message frames, tabs, sidebar -- goes
-- with them. Follow the chat frames onto whichever host Blizzard picked, and
-- back to UIParent when the editor closes. Every frame moved here is ours.
local _panelHost = UIParent
local function PanelHost()
    return FCF_GetCurrentFullScreenFrame and FCF_GetCurrentFullScreenFrame() or UIParent
end

local function ReseatPanel(frame, owner)
    if not frame then
        return
    end
    local p = frame:GetParent()
    if p ~= owner and (p == UIParent or p == _panelHost) then
        FrameUtil.SetParentMaintainRenderLayering(frame, owner)
    end
end

function CHAT.ApplyPanelHost()
    local owner = PanelHost()
    for index = 1, 20 do
        local castFrame = _G["ChatFrame" .. index]
        if castFrame then
            local skinData = CFD(castFrame)
            ReseatPanel(skinData.bg, owner)
            ReseatPanel(skinData.sidebar, owner)
            -- Moves only while it is seated on the chat panel; on the sidebar
            -- seat it is a child of a frame this pass already moved.
            ReseatPanel(skinData.scrollBtn, owner)
        end
    end
    ReseatPanel(mod._chatTabStrip, owner)
    ReseatPanel(mod._chatBgExt, owner)
    ReseatPanel(mod._chatPanelBorder, owner)
    ReseatPanel(mod._sidebarSeparateBorder, owner)
    ReseatPanel(mod._chatHoverOverlay, owner)
    _panelHost = owner
end

-- The on-demand popups are built the first time they are used and can be built
-- on either side of an editor session, so they seat themselves on show instead
-- of riding the pass above.
function CHAT.HostPopup(frame)
    local owner = PanelHost()
    if frame:GetParent() ~= owner then
        FrameUtil.SetParentMaintainRenderLayering(frame, owner)
    end
end

-- The main window ships with clamp-rect insets that extend its clamp box
-- ~25-60px past every edge (phantom room reserved for the stock tab strip
-- and edit box). Our panel draws its own tabs and input INSIDE the window,
-- so the reservation only blocks corner placement: the screen clamp pins
-- the frame that far from every edge, which also silently eats unlock-mode
-- drags and arrow nudges toward a corner (the anchor moves, the resolved
-- rect stays pinned). Zero the insets so the clamp lands exactly at the
-- screen edges; clamped-to-screen itself stays on as the cannot-lose-the-
-- window safety net. Compare-gated (write-free when settled) because dock
-- passes can rewrite the insets; asserted from the state sync and the
-- position chokepoint.
-- Stock styles show Blizzard's own art round the frame instead: the insets
-- then reserve exactly that (the border STOCK_BG_X + 4 each side, the tab
-- row above, the input box below), not the Edit Mode selection's wider box,
-- so the art stays on screen and a corner placement still resolves close.
CHAT.STOCK_CLAMP_TOP, CHAT.STOCK_CLAMP_BOTTOM = 35, 34
local function EnsureChatClampInsets()
    local cf1 = _G.ChatFrame1
    if not (cf1 and cf1.GetClampRectInsets) then
        return
    end
    local wl, wr, wt, wb = 0, 0, 0, 0
    if mod.ChatStock() then
        local posX = (CHAT.STOCK_BG_X or 8) + 4
        wl, wr, wt, wb = -posX, posX, CHAT.STOCK_CLAMP_TOP, -CHAT.STOCK_CLAMP_BOTTOM
        -- WoW Forever: the kit's frame reaches FV.X past each side and its
        -- own input box further down.
        if mod.ChatForever() then
            wl, wr, wb = -CHAT.FV.X, CHAT.FV.X, -CHAT.FV_PanelDrop(GetEditBoxHeight())
        end
    end
    local l, region, t, b = cf1:GetClampRectInsets()
    if l ~= wl or region ~= wr or t ~= wt or b ~= wb then
        cf1:SetClampRectInsets(wl, wr, wt, wb)
        -- A rect the clamp pinned under the other insets stays pinned until
        -- the anchors are written again (they still read as ours), so the
        -- next placement re-anchors instead of trusting its compare gate.
        mod._chatReanchor = true
    end
end

-- Stock styles: Blizzard seats a chat frame's background 2px past the text's
-- left edge but 15px past its right, room for its own scroll bar, which never
-- shows on a window our engine renders (ours rides inside the right edge),
-- and its input box from 3px outside the background's left edge to 1px
-- outside its right. Re-seat the background symmetric, STOCK_BG_X past each
-- side (about the same width, centred on the text), the input box with it
-- (keeping Blizzard's box-to-background spacing), and the undocked window's
-- size grabber (on the background's corner) out to the border's outer edge
-- so it stays off the text. Only x offsets change: each anchor's point,
-- relative frame and y offset are read back and kept. Permanent windows
-- only, minus the combat log: temporary whisper windows keep Blizzard's
-- layout whole (their input boxes are never touched), and the combat log
-- shows Blizzard's own scroll bar in that reserve and has its background
-- re-seated by Blizzard on every dock update. Blizzard anchors the rest only
-- at load (background, grabber) or in the template (input box), so each
-- window is seated once and stamped. Armed from the deferred PEW pass, never
-- inside PLAYER_LOGIN (the login dock pass must not read these anchors), and
-- run from the state sync, whose passes are all our own deferred contexts.
CHAT.STOCK_BG_X = 8
CHAT._stockBgPts = {}
-- Rewrites the x of every LEFT/RIGHT anchor on region r; true once settled
-- (nothing to seat, or seated), false when a secret anchor held it off.
function CHAT._SeatStockX(region, lx, rx)
    if not (region and region.GetNumPoints) then
        return true
    end
    local sec = _G.issecretvalue
    local pts, c, differs = CHAT._stockBgPts, 0, false
    for index = 1, region:GetNumPoints() do
        local p, rel, rp, posX, posY = region:GetPoint(index)
        if not p or (sec and (sec(posX) or sec(posY))) then
            for jdx = 1, c do
                pts[jdx] = nil
            end
            return false
        end
        local wanted = (p:find("LEFT") and lx) or (p:find("RIGHT") and rx) or nil
        if wanted and posX ~= wanted then
            differs = true
        end
        pts[c + 1], pts[c + 2], pts[c + 3], pts[c + 4] = p, rel, rp, posY
        c = c + 4
    end
    if differs then
        for jdx = 1, c, 4 do
            local p = pts[jdx]
            local posX = (p:find("LEFT") and lx) or (p:find("RIGHT") and rx) or nil
            if posX then
                region:SetPoint(p, pts[jdx + 1], pts[jdx + 2], posX, pts[jdx + 3])
            end
        end
    end
    for jdx = 1, c do
        pts[jdx] = nil
    end
    return true
end
function CHAT.SeatStockBackground(castFrame)
    if not (castFrame and CHAT._stockSeatArmed) then
        return
    end
    local skinData = CFD(castFrame)
    if skinData.stockSeated then
        return
    end
    local ident = castFrame:GetID()
    local cc = Constants and Constants.ChatFrameConstants
    if not ident or ident < 1 or ident == 2 or ident > ((cc and cc.MaxChatWindows) or 10) then
        skinData.stockSeated = true
        return
    end
    local X = CHAT.STOCK_BG_X
    local success = CHAT._SeatStockX(castFrame.Background, -X, X)
    -- Input box: TOPLEFT on the chat frame's BOTTOMLEFT (3px outside the
    -- background's left edge), RIGHT on its scroll bar's RIGHT (the bar is
    -- 8px wide from the chat frame's right edge; 1px outside the background).
    success = CHAT._SeatStockX(castFrame.editBox, -X - 3, X + 1 - 8) and success
    -- Size grabber (undocked windows; the main window's never shows):
    -- BOTTOMRIGHT on the background's, out to the border's outer edge.
    if ident ~= 1 then
        success = CHAT._SeatStockX(castFrame.ResizeButton, 4, 4) and success
    end
    if success then
        skinData.stockSeated = true
    end
end

-- State sync for what the panels lost by no longer being chat frame children,
-- plus two Blizzard buttons hidden by alpha: Blizzard fades ButtonFrame /
-- ScrollToBottomButton back in on hover (UIFrameFadeIn drives only their
-- alpha) and re-levels chat frames on dock passes. ButtonFrame's minimize
-- button keeps its own art and inherits its alpha, so DOCKED ONLY below:
-- undocked, Blizzard's own hover fade owns that alpha and this would fight
-- it every pass. Runs from the interaction follower and the deferred event
-- passes. The stack-hidden gate keeps the shown-follow from re-showing
-- panels the full-hide put away.
function CHAT.SyncChatFrameState()
    if CHAT.SuppressChatEditModeSelection then
        CHAT.SuppressChatEditModeSelection()
    end
    EnsureChatClampInsets()
    -- Size drift self-heal: Edit Mode's late layout passes can re-rect the
    -- main window through paths the ApplySystemAnchor guard never sees,
    -- leaving the frame on its stale explicit size while the panel still
    -- shows ours. Verify the saved size holds and re-assert on drift.
    -- Compare-gated (two reads when settled); suspended during the grip
    -- drag and unlock sessions, whose live geometry rules.
    local cfgSz = CHAT.DB()
    local place = cfgSz and cfgSz.chatPosition
    local sz = place and cfgSz.chatSize
    if
        sz
        and sz.w
        and sz.h
        and not mod._chatSizingActive
        and not (_G.CludesUI and _G.CludesUI._unlockActive)
    then
        local cf1s = _G.ChatFrame1
        -- Armed only after the settled-sight apply (the anchor guard is
        -- installed there): position ownership must never begin early, or
        -- this heal re-rects chat mid-login while Blizzard's dock passes are
        -- still resolving (ghost tab strip built against half-resolved
        -- geometry = invisible tabs until the next pass).
        local d1 = cf1s and CFD(cf1s)
        if d1 and d1.anchorGuarded then
            local wid = cf1s:GetWidth()
            local hgt = cf1s:GetHeight()
            local isec = _G.issecretvalue
            local drift = false
            if
                wid
                and hgt
                and not (isec and (isec(wid) or isec(hgt)))
                and (math.abs(wid - sz.w) > 1.5 or math.abs(hgt - sz.h) > 1.5)
            then
                drift = true
            end
            -- Position drift too: Edit Mode's late writes move the rect as
            -- well as resizing it.
            local tx, ty
            if not drift and mod.ChatSavedLeftBottom then
                tx, ty = mod.ChatSavedLeftBottom(place, sz.w, sz.h, cf1s)
            end
            if tx then
                local l, b = cf1s:GetLeft(), cf1s:GetBottom()
                -- Stock styles clamp against their art's reserve: compare with
                -- the spot the clamp lets the frame reach, or a position saved
                -- nearer an edge (the CludesUI look clamps at zero) would
                -- read as drift on every pass and never converge.
                if mod.ChatStock() then
                    local il, ir, it, ib = cf1s:GetClampRectInsets()
                    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
                    if il and sw and sh then
                        tx = math.max(-il, math.min(tx, sw - ir - sz.w))
                        ty = math.max(-ib, math.min(ty, sh - it - sz.h))
                    end
                end
                if
                    l
                    and b
                    and not (isec and (isec(l) or isec(b)))
                    and (math.abs(l - tx) > 1.5 or math.abs(b - ty) > 1.5)
                then
                    drift = true
                end
            end
            if drift and CHAT.ApplyChatPosition then
                CHAT.ApplyChatPosition()
            end
        end
    end
    -- Stock styles reveal Blizzard's own background ON the chat frame, and
    -- the chat frame (a toplevel frame) draws its art over our separately
    -- parented text at ANY level within its own strata (measured: the frame
    -- at LOW 5 painted over our text container at LOW 11). So the panel --
    -- and the text frame it hosts -- runs one strata up, in MEDIUM, where the
    -- tab strip and the panel border already live; it takes no mouse, so
    -- hyperlink hit zones are unaffected. The CludesUI look keeps the
    -- chat frame's strata, one level below it, and so does WoW Forever
    -- (Blizzard's art stripped; the hosted combat log must draw over ours).
    local stockLvl = mod.ChatStockArt()
    for index = 1, 20 do
        local castFrame = _G["ChatFrame" .. index]
        if castFrame then
            local isShown = castFrame:IsShown()
            if isShown then
                -- Docked only: undocked, Blizzard's own hover fade owns this
                -- alpha (0.2 idle, 1 on hover), and re-asserting here would
                -- fight it every pass -- the minimize button, its child, kept
                -- flickering with that fight even after btnFrame's own art was
                -- emptied. GetAlpha reads secret on chat-roleset widgets in
                -- lockdown; a secret skips the compare and re-asserts.
                local bf = castFrame.isDocked and _G["ChatFrame" .. index .. "ButtonFrame"]
                local bfA = bf and bf:GetAlpha()
                if bfA and ((issecretvalue and issecretvalue(bfA)) or bfA ~= 0) then
                    bf:SetAlpha(0)
                end
                local scrollBar = castFrame.ScrollToBottomButton
                local sbA = scrollBar and scrollBar:GetAlpha()
                if sbA and ((issecretvalue and issecretvalue(sbA)) or sbA ~= 0) then
                    scrollBar:SetAlpha(0)
                end
            end
            -- Stock styles: each permanent window's art seated once (stamped).
            if stockLvl then
                CHAT.SeatStockBackground(castFrame)
            end
            local backdrop = CFD(castFrame).bg
            if backdrop and not mod._chatStackHidden then
                if backdrop:IsShown() ~= isShown then
                    backdrop:SetShown(isShown)
                end
                if isShown then
                    if stockLvl then
                        local lvl = castFrame:GetFrameLevel() + 1
                        if backdrop:GetFrameLevel() ~= lvl then
                            backdrop:SetFrameLevel(lvl)
                        end
                        if CHAT.EngineLevelWindow then
                            CHAT.EngineLevelWindow(castFrame)
                        end
                    else
                        local lvl = upper(0, castFrame:GetFrameLevel() - 1)
                        if backdrop:GetFrameLevel() ~= lvl then
                            backdrop:SetFrameLevel(lvl)
                        end
                    end
                    local st = stockLvl and "MEDIUM" or castFrame:GetFrameStrata()
                    if backdrop:GetFrameStrata() ~= st then
                        backdrop:SetFrameStrata(st)
                    end
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Interaction follower: the ONLY recurring driver in this module, HIDDEN
--  whenever chat is not being interacted with. A chat frame's rect / the
--  dock's state can only change via an event the deferred passes already
--  catch (login, dock config, scale, Edit Mode commits, whisper windows) or a
--  mouse/Edit Mode interaction on a widget we hook (tab/resize/sidebar hover,
--  Edit Mode show/hide). The follower arms on those edges, follows per-frame
--  while armed, then disarms to hidden -- zero recurring work or allocations
--  while idle. Accepted gap: a frame moved by another addon or a /run with no
--  event and no nearby mouse only heals on the next event/interaction.
-------------------------------------------------------------------------------
do
    local follower = CreateFrame("Frame")
    follower:Hide()
    local hoverCount = 0
    local lingerUntil = 0
    local editMode = false
    local unlockHold = false
    local accum = 0
    local lastSelected
    local lastShown = {}
    local lastFontSize = {}
    local lastDockCount

    -- Seed before the first interaction so a fast tab-menu change is still
    -- recognized as a change from the settled Blizzard value.
    for index = 1, 20 do
        local castFrame = _G["ChatFrame" .. index]
        if castFrame and castFrame.GetFont then
            local size = GetFrameFontSize(index)
            if size and size > 0 then
                lastFontSize[index] = size
            end
        end
    end

    follower:SetScript("OnUpdate", function(_, elapsed)
        -- Geometry every frame while armed: drags need per-frame follow.
        CHAT.PositionChatPanelsNow()
        -- Dock membership, every frame (one table-length read): closing a
        -- NON-selected docked window flips nothing else we watch -- its
        -- frame was already hidden by the dock and selection stays put.
        if GENERAL_CHAT_DOCK and GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES then
            local num = #GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES
            if num ~= lastDockCount then
                lastDockCount = num
                -- Ghosts correct SYNCHRONOUSLY: this tick is our own
                -- execution, after the click that changed the dock but
                -- before this frame renders. A queued pass would paint one
                -- frame of a ghost stretched on the dying tab.
                if CHAT.TabsRefreshNow then
                    CHAT.TabsRefreshNow()
                end
                if CHAT.QueueTabPass then
                    CHAT.QueueTabPass()
                end
            end
        end
        -- State compares are cheaper at a coarse cadence.
        accum = accum + elapsed
        if accum < 0.1 then
            return
        end
        accum = 0
        -- Edit Mode self-heal: OnHide is the normal disarm; this covers a missed
        -- one (reload inside Edit Mode etc.).
        if editMode and EditModeManagerFrame and not EditModeManagerFrame:IsShown() then
            editMode = false
        end
        -- Selected dock window changed (tab click, tab menu action).
        if GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow then
            local sel = FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
            if sel ~= lastSelected then
                lastSelected = sel
                if CHAT.QueueTabPass then
                    CHAT.QueueTabPass()
                end
                -- Stock sidebar: the scroll flash follows the selected window.
                if CHAT.SB_FlashSync then
                    CHAT.SB_FlashSync()
                end
            end
            -- Blizzard Style sidebar backdrop: the selected window's stored
            -- colour (tab-menu colour and opacity edits land while armed).
            if CHAT.SB_SyncBackdrop then
                CHAT.SB_SyncBackdrop()
            end
        end
        -- Blizzard's tab menu writes the frame font directly and does not emit
        -- UPDATE_CHAT_WINDOWS. Mirror the changed stored size into the CUI
        -- profile while this existing interaction-only watcher is armed, then
        -- refresh our visible copy from Blizzard's storage.
        for index = 1, 20 do
            local castFrame = _G["ChatFrame" .. index]
            if castFrame and castFrame.GetFont then
                local size = GetFrameFontSize(index)
                if size and size ~= lastFontSize[index] then
                    if lastFontSize[index] then
                        local conf = CHAT.DB()
                        if conf and conf.chatFontSize ~= size then
                            conf.chatFontSize = size
                        end
                    end
                    if lastFontSize[index] and CHAT.EngineApplyFontTo then
                        CHAT.EngineApplyFontTo(castFrame)
                    end
                    lastFontSize[index] = size
                end
            end
        end
        -- A frame appeared or closed (tab menu close, window created).
        local shownChanged = false
        for index = 1, 20 do
            local castFrame = _G["ChatFrame" .. index]
            local isShown = castFrame and castFrame:IsShown() or false
            if isShown ~= lastShown[index] then
                lastShown[index] = isShown
                shownChanged = true
            end
        end
        if shownChanged and CHAT.QueueFullPass then
            CHAT.QueueFullPass()
        end
        CHAT.SyncChatFrameState()
        -- Disarm: nothing hovered, Edit Mode closed, linger expired, no open
        -- context menu. The linger covers quick menu clicks; the menu check
        -- covers long browses -- tab menu actions (close, rename, new window)
        -- land while the mouse has been in the menu far past the linger, and
        -- the shown/selection watches above must see their results.
        local menuOpen = Menu and Menu.GetManager and Menu.GetManager():IsAnyMenuOpen()
        if
            hoverCount == 0
            and not editMode
            and not unlockHold
            and not menuOpen
            and GetTime() >= lingerUntil
        then
            CHAT.PositionChatPanelsNow()
            follower:Hide()
        end
    end)

    -- Hover refcount from widget OnEnter/OnLeave hooks (tabs, resize buttons,
    -- sidebar). OnLeave fires when a hovered frame hides, so the count cannot
    -- leak across dock rebuilds.
    function CHAT.FollowArm()
        hoverCount = hoverCount + 1
        follower:Show()
    end
    function CHAT.FollowRelease()
        hoverCount = upper(0, hoverCount - 1)
        if hoverCount == 0 then
            lingerUntil = GetTime() + 4
        end
    end
    -- Edit Mode session: chat can be dragged/resized with the mouse far from
    -- any of our hover widgets (the Selection overlay occludes them).
    function CHAT.FollowArmEditMode(on)
        editMode = on and true or false
        if editMode then
            follower:Show()
        end
    end
    -- Unlock-mode session hold: the Chat mover drags ChatFrame1 with the
    -- cursor over OUR mover proxy, not over any arming widget -- without
    -- this hold the panel and text freeze mid-drag until the next pass.
    -- Separate from the Edit Mode flag: its self-heal would clear a shared
    -- flag whenever the Edit Mode manager is closed (always, in unlock).
    function CHAT.FollowArmUnlock(on)
        unlockHold = on and true or false
        if unlockHold then
            follower:Show()
        end
    end
end

-- Main-chunk locals the CUI_Chat_*.lua files re-import by name.
-- bgRSetters and the lists beside it: every file that reads one of these
-- shared locals keeps its own copy and adds a setter here; every write goes
-- through the Set<Name> function built below, which runs them all. BG_R and
-- the other shared locals stand in the table with their value at load, for
-- the copies to start from.
-- broken: true while an CUI_Chat_*.lua file loads; a file that fails leaves
-- it set, and the files behind it return at their first lines.
CludesUI.NewInternals(mod, "_internals", {
    _chatAlphaCurrent = _chatAlphaCurrent,
    _chatFadeFrame = _chatFadeFrame,
    _sidebarFadeAlpha = _sidebarFadeAlpha,
    _sidebarFadeTarget = _sidebarFadeTarget,
    _sidebarMouseoverLayoutVisible = _sidebarMouseoverLayoutVisible,
    BG_A = BG_A,
    BG_B = BG_B,
    BG_G = BG_G,
    BG_R = BG_R,
    CFD = CFD,
    EnsureChatClampInsets = EnsureChatClampInsets,
    EnsureDB = EnsureDB,
    FADE_IN_DURATION = FADE_IN_DURATION,
    FADE_OUT_DURATION = FADE_OUT_DURATION,
    GetEditBoxFont = GetEditBoxFont,
    GetEditBoxFontSize = GetEditBoxFontSize,
    GetEditBoxHeight = GetEditBoxHeight,
    GetFont = GetFont,
    GetFrameFontSize = GetFrameFontSize,
    GetIdleFadeAlpha = GetIdleFadeAlpha,
    GetInnerBorderColor = GetInnerBorderColor,
    GetOutlineFlag = GetOutlineFlag,
    GetTabAreaHeight = GetTabAreaHeight,
    HideSidebarIconTooltip = HideSidebarIconTooltip,
    IDLE_FADE_OUT_DURATION = IDLE_FADE_OUT_DURATION,
    ShowSidebarIconTooltip = ShowSidebarIconTooltip,
    bgRSetters = {
        function(val)
            BG_R = val
        end,
    },
    bgGSetters = {
        function(val)
            BG_G = val
        end,
    },
    bgBSetters = {
        function(val)
            BG_B = val
        end,
    },
    bgASetters = {
        function(val)
            BG_A = val
        end,
    },
    sidebarLayoutVisibleSetters = {
        function(val)
            _sidebarMouseoverLayoutVisible = val
        end,
    },
    sidebarFadeTargetSetters = {
        function(val)
            _sidebarFadeTarget = val
        end,
    },
    sidebarFadeAlphaSetters = {
        function(val)
            _sidebarFadeAlpha = val
        end,
    },
    sidebarFadeFrameSetters = {
        function(val)
            _sidebarFadeFrame = val
        end,
    },
    chatAlphaCurrentSetters = {
        function(val)
            _chatAlphaCurrent = val
        end,
    },
    visChatVisibleSetters = {},
    idleFadeActiveSetters = {},
}, {
    SetBgR = "bgRSetters",
    SetBgG = "bgGSetters",
    SetBgB = "bgBSetters",
    SetBgA = "bgASetters",
    SetSidebarLayoutVisible = "sidebarLayoutVisibleSetters",
    SetSidebarFadeTarget = "sidebarFadeTargetSetters",
    SetSidebarFadeAlpha = "sidebarFadeAlphaSetters",
    SetSidebarFadeFrame = "sidebarFadeFrameSetters",
    SetChatAlphaCurrent = "chatAlphaCurrentSetters",
    SetVisChatVisible = "visChatVisibleSetters",
    SetIdleFadeActive = "idleFadeActiveSetters",
})
-- The Set<Name> functions this file calls itself (declared above BG_R).
do
    local Inner = mod._internals
    SetBgR, SetBgG, SetBgB, SetBgA = Inner.SetBgR, Inner.SetBgG, Inner.SetBgB, Inner.SetBgA
    SetSidebarLayoutVisible, SetSidebarFadeFrame = Inner.SetSidebarLayoutVisible, Inner.SetSidebarFadeFrame
    SetSidebarFadeTarget, SetSidebarFadeAlpha = Inner.SetSidebarFadeTarget, Inner.SetSidebarFadeAlpha
end
