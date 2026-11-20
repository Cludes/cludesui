if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIChat_SidebarStock.lua
--
--  The chat sidebar under the stock styles (Global Settings > Style):
--  Blizzard Style dresses it as Blizzard's own chat button column (the
--  ButtonFrame seat, a copy of its bordered backdrop in the window colour,
--  the chat button plates, the QuickJoin friends button, the voice plate, the
--  chat menu bubble, the settings gear and the return-to-bottom arrow);
--  Classic WoW UI dresses it as the vanilla column (bevelled square buttons,
--  the chat menu bubble -- on Settings unless Chat Menu is built -- the
--  scroll-down button, no backdrop). Where Blizzard has no art for one of our
--  buttons (guild, copy, portals) our own glyph sits on the kit's button in
--  Blizzard's gold. Durability matches them (our glyph in gold on the kit's
--  button), tinted by the worst equipment alert. WoW Forever's kit (bronze
--  square plates, tan glyphs) lives in CludesUIChat_Forever.lua.
--
--  Everything here dresses OUR sidebar and buttons (UIParent-parented frames
--  the chat module creates); no Blizzard frame is touched. Loaded after the
--  main chat file: at load it only builds static data tables. The main file
--  reads ECHAT.SB_KIT (nil on the CludesUI look, so each hook there costs
--  one nil test) and calls the helpers below.
-------------------------------------------------------------------------------
local _, mod = ...
local CUI = _G.CludesUI
local CHAT = mod.ECHAT
if not CHAT or not CUI then
    return
end
local CFD = CUI._chatCFD
local issecretvalue = _G.issecretvalue

local MEDIA = "Interface\\AddOns\\CludesUIChat\\Media\\"
local HILIGHT = { file = "Interface\\Buttons\\UI-Common-MouseHilight" }
local GOLD_R, GOLD_G, GOLD_B = 1, 0.82, 0

-- Our glyph drawn whole at 18x18 in gold (the ink fills 60-83% of the box,
-- about Blizzard's 15px icon atlas).
local function PNG(name)
    return { file = MEDIA .. name, w = 18, h = 18, gold = true }
end
-- A kit entry: the base button's fields, then the entry's own.
local function Entry(base, tbl)
    tbl = tbl or {}
    if base then
        for k, val in pairs(base) do
            if tbl[k] == nil then
                tbl[k] = val
            end
        end
    end
    return tbl
end
CHAT.SB_Entry = Entry -- the WoW Forever kit (CludesUIChat_Forever.lua)

-- Button bases. w/h at scale 1; padT/padB = the art's transparent rows (the
-- visible gap between icons is measured art to art).
local PLATE = { -- Blizzard's chat button plate (the voice button's)
    w = 27,
    h = 26,
    padT = 1,
    padB = 1,
    n = { atlas = "chatframe-button-up" },
    p = { atlas = "chatframe-button-down" },
    hl = { atlas = "chatframe-button-highlight" },
    hlBlend = "ADD",
    push = true,
}
local QJ = { -- the QuickJoin friends button, count inside
    w = 32,
    h = 32,
    padT = 0,
    padB = 0,
    count = "inside",
    n = { atlas = "quickjoin-button-friendslist-up" },
    p = { atlas = "quickjoin-button-friendslist-down" },
    hl = HILIGHT,
    hlBlend = "ADD",
}
local BEVEL = { -- the vanilla square chat bevel (the gold square button, desaturated)
    w = 32,
    h = 32,
    padT = 3,
    padB = 3,
    inset = 0.4,
    n = { file = "Interface\\Buttons\\UI-SquareButton-Up", desat = true },
    p = { file = "Interface\\Buttons\\UI-SquareButton-Down", desat = true },
    hl = HILIGHT,
    hlBlend = "ADD",
    push = true,
}
local BUBBLE = { -- Blizzard's chat menu button (the same art on live and WoW Forever)
    w = 32,
    h = 32,
    padT = 3,
    padB = 3,
    n = { file = "Interface\\ChatFrame\\UI-ChatIcon-Chat-Up" },
    p = { file = "Interface\\ChatFrame\\UI-ChatIcon-Chat-Down" },
    hl = HILIGHT,
    hlBlend = "ADD",
}
local GEAR = { -- the Damage Meter settings gear: the whole button is the art
    idle = "common-dropdown-a-button-settings-shadowless",
    over = "common-dropdown-a-button-settings-hover-shadowless",
    down = "common-dropdown-a-button-settings-pressed-shadowless",
    both = "common-dropdown-a-button-settings-pressedhover-shadowless",
}
local GEAR_PROBE = { atlas = GEAR.idle }

CHAT.SB_KITS = {
    blizzard = {
        col = { dx = 1, top = -7, bot = 10 },
        gap = 4,
        backdrop = true,
        voiceState = true,
        flash = "fade",
        friends = Entry(QJ),
        guild = Entry(PLATE, {
            count = "below",
            glyph = {
                { atlas = "friends-icon-tab-guildmates", w = 17, h = 17 },
                PNG("chat_guild.png"),
            },
        }),
        durability = Entry(PLATE, { count = "below", alert = true, glyph = { PNG("chat_durability.png") } }),
        copy = Entry(PLATE, { glyph = { PNG("chat_copy.png") } }),
        portals = Entry(PLATE, { glyph = { PNG("chat_portal.png") } }),
        voice = Entry(PLATE, { glyph = { { atlas = "chatframe-button-icon-voicechat", w = 15, h = 15 } } }),
        chatmenu = Entry(BUBBLE),
        settings = {
            w = 27,
            h = 27,
            padT = 1,
            padB = 1,
            gear = true,
            alt = Entry(PLATE, { glyph = { PNG("chat_settings.png") } }),
        },
        scroll = {
            sidebar = {
                w = 32,
                h = 32,
                n = { file = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up" },
                p = { file = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down" },
                hl = HILIGHT,
                hlBlend = "ADD",
                flashArt = { file = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up" },
            },
            chat = {
                w = 17,
                h = 15,
                n = { atlas = "minimal-scrollbar-arrow-returntobottom" },
                p = { atlas = "minimal-scrollbar-arrow-returntobottom-down" },
                hl = { atlas = "minimal-scrollbar-arrow-returntobottom-over" },
                flashArt = { atlas = "minimal-scrollbar-arrow-returntobottom" },
            },
        },
    },
    classic = {
        col = { dx = 1, top = -4, bot = 4 },
        gap = 4,
        flash = "blink",
        friends = Entry(QJ),
        guild = Entry(BEVEL, { count = "below", glyph = { PNG("chat_guild.png") } }),
        durability = Entry(BEVEL, { count = "below", alert = true, glyph = { PNG("chat_durability.png") } }),
        copy = Entry(BEVEL, {
            glyph = {
                {
                    file = "Interface\\Buttons\\UI-GuildButton-PublicNote-Up",
                    probe = true,
                    tc = { 0.125, 0.875, 0.0625, 0.9375 },
                    w = 12,
                    h = 14,
                },
                PNG("chat_copy.png"),
            },
        }),
        portals = Entry(BEVEL, { glyph = { PNG("chat_portal.png") } }),
        voice = Entry(BEVEL, {
            glyph = {
                {
                    file = "Interface\\Common\\VoiceChat-Speaker",
                    tc = { 0, 0.59375, 0.15625, 0.90625 },
                    w = 11,
                    h = 14,
                },
            },
        }),
        chatmenu = Entry(BUBBLE),
        -- The bubble is the chat menu's: while Chat Menu is built, our cog on
        -- the bevel instead.
        settings = Entry(BUBBLE, { withChatMenu = Entry(BEVEL, { glyph = { PNG("chat_settings.png") } }) }),
        scroll = {
            sidebar = {
                w = 32,
                h = 32,
                n = {
                    file = "Interface\\ChatFrame\\UI-ChatIcon-ScrollEnd-Up",
                    probe = true,
                    alt = { file = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up" },
                },
                p = {
                    file = "Interface\\ChatFrame\\UI-ChatIcon-ScrollEnd-Down",
                    probe = true,
                    alt = { file = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down" },
                },
                hl = HILIGHT,
                hlBlend = "ADD",
                flashArt = {
                    file = "Interface\\ChatFrame\\UI-ChatIcon-BlinkHilight",
                    probe = true,
                    alt = HILIGHT,
                },
            },
        },
    },
}
CHAT.SB_KITS.classic.scroll.chat = Entry(CHAT.SB_KITS.classic.scroll.sidebar, { w = 24, h = 24 })

-- Worst equipment alert -> durability glyph tint: the kits' gold while all is
-- fine (full opacity, so it never reads as disabled), then orange (damaged)
-- and red (broken); Blizzard's damaged yellow is nearly the gold. An entry's
-- own alertColors would override it.
CHAT.SB_ALERT = { [0] = { GOLD_R, GOLD_G, GOLD_B, 1 }, { 1, 0.5, 0.1, 1 }, { 0.93, 0.07, 0.07, 1 } }
CHAT.SB_REF = {
    friends = "friendsBtn",
    guild = "guildBtn",
    durability = "durabilityBtn",
    copy = "copyBtn",
    portals = "portalBtn",
    voice = "voiceBtn",
    chatmenu = "chatMenuBtn",
    settings = "settingsBtn",
}
CHAT._sbBdMemo = {}

-- The stock kit for this session (the style is latched before the sidebar
-- is built). The two hot hooks the main file tests stay nil on the
-- CludesUI look.
function CHAT.SB_Latch()
    local key = mod.ChatStock and mod.ChatStock() and mod.ChatStyle()
    -- WoW Forever: the kit's bronze square buttons.
    if key and mod.ChatForever() and CHAT.SB_KITS.forever then
        key = "forever"
    end
    local kit = key and CHAT.SB_KITS[key] or nil
    CHAT.SB_KIT = kit
    CHAT.SB_SyncBackdrop = (kit and kit.backdrop) and CHAT._SB_SyncBackdropImpl or nil
    CHAT.SB_FlashSync = kit and CHAT._SB_FlashSyncImpl or nil
end

-- Art present in this client (memoised on our own data table, once per
-- session): atlases through GetAtlasInfo, probed files through their id.
function CHAT.SB_ArtOK(e)
    if not e then
        return false
    end
    if e._ok == nil then
        if e.atlas then
            e._ok = (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(e.atlas)) and true
                or false
        elseif e.probe then
            local frame = _G.GetFileIDFromPath
            e._ok = (frame and frame(e.file)) and true or false
        else
            e._ok = true
        end
    end
    return e._ok
end
local function Pick(e)
    while e and not CHAT.SB_ArtOK(e) do
        e = e.alt
    end
    return e
end
local function SetStateArt(button, which, e, blend)
    if not e then
        return
    end
    if which == "Highlight" then
        if e.atlas then
            if blend then
                button:SetHighlightAtlas(e.atlas, blend)
            else
                button:SetHighlightAtlas(e.atlas)
            end
        else
            button:SetHighlightTexture(e.file, blend)
        end
        return
    end
    if e.atlas then
        button["Set" .. which .. "Atlas"](button, e.atlas)
    else
        button["Set" .. which .. "Texture"](button, e.file)
        local t = button["Get" .. which .. "Texture"](button)
        if t and e.desat then
            t:SetDesaturated(true)
        end
    end
end

-- Default sidebar width: Blizzard's 29px column (30 = the slider minimum),
-- or the kit's own column, following Icon Size; 40 on the CludesUI look.
function CHAT.SidebarWidthDefault()
    if not CHAT.SB_KIT then
        return 40
    end
    return math.max(30, math.floor((CHAT.SB_KIT.colW or 29) * (CHAT.DB().sidebarIconScale or 1) + 0.5))
end

-- The sidebar on the kit's column seat: Blizzard's ButtonFrame rect (its
-- right edge 1px inside our panel, which sits 4px outside the chat
-- background), mirrored for Show Sidebar on Right; Separate Sidebar adds its
-- gap.
function CHAT.SB_Place(scrollBar, bgTex, conf)
    local c = CHAT.SB_KIT.col
    local gap = (conf.sidebarSeparate == true) and (conf.sidebarSeparateSpacing or 8) or 0
    if conf.sidebarRight then
        scrollBar:SetPoint("TOPLEFT", bgTex, "TOPRIGHT", -c.dx + gap, c.top)
        scrollBar:SetPoint("BOTTOMLEFT", bgTex, "BOTTOMRIGHT", -c.dx + gap, c.bot)
    else
        scrollBar:SetPoint("TOPRIGHT", bgTex, "TOPLEFT", c.dx - gap, c.top)
        scrollBar:SetPoint("BOTTOMRIGHT", bgTex, "BOTTOMLEFT", c.dx - gap, c.bot)
    end
end

-- Blizzard Style: a copy of the chat window's bordered backdrop (the
-- FloatingBorderedFrame template Blizzard hangs on its ButtonFrame) on a
-- child of our sidebar, under the buttons, in the window colour.
local BD = "Interface\\ChatFrame\\"
function CHAT.SB_BuildBackdrop(sidebar, skinData)
    local edge = CreateFrame("Frame", nil, sidebar)
    edge:SetAllPoints()
    edge:SetFrameLevel(sidebar:GetFrameLevel())
    edge:EnableMouse(false)
    local fillTex = edge:CreateTexture(nil, "BACKGROUND")
    fillTex:SetPoint("TOPLEFT", sidebar, "TOPLEFT", -2, 3)
    fillTex:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 2, -6)
    local function Corner(anchorPoint, posX, posY, left, right, top, bottom)
        local c = edge:CreateTexture(nil, "BORDER")
        c:SetTexture(BD .. "UI-ChatFrame-BorderCorner")
        c:SetSize(8, 8)
        c:SetPoint(anchorPoint, fillTex, anchorPoint, posX, posY)
        c:SetTexCoord(left, right, top, bottom)
        return c
    end
    local tl = Corner("TOPLEFT", -4, 4, 0, 1, 0, 1)
    local bl = Corner("BOTTOMLEFT", -4, -4, 0, 1, 1, 0)
    local tr = Corner("TOPRIGHT", 4, 4, 1, 0, 0, 1)
    local br = Corner("BOTTOMRIGHT", 4, -4, 1, 0, 1, 0)
    local leftX = edge:CreateTexture(nil, "BORDER")
    leftX:SetTexture(BD .. "UI-ChatFrame-BorderLeft", nil, "REPEAT")
    leftX:SetVertTile(true)
    leftX:SetWidth(16)
    leftX:SetPoint("TOPLEFT", tl, "BOTTOMLEFT")
    leftX:SetPoint("BOTTOMLEFT", bl, "TOPLEFT")
    local right = edge:CreateTexture(nil, "BORDER")
    right:SetTexture(BD .. "UI-ChatFrame-BorderLeft", nil, "REPEAT")
    right:SetVertTile(true)
    right:SetWidth(16)
    right:SetTexCoord(1, 0, 0, 1)
    right:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT")
    right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
    local bottom = edge:CreateTexture(nil, "BORDER")
    bottom:SetTexture(BD .. "UI-ChatFrame-BorderTop", "REPEAT")
    bottom:SetHorizTile(true)
    bottom:SetHeight(16)
    bottom:SetTexCoord(0, 1, 1, 0)
    bottom:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT")
    bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
    local topY = edge:CreateTexture(nil, "BORDER")
    topY:SetTexture(BD .. "UI-ChatFrame-BorderTop", "REPEAT")
    topY:SetHorizTile(true)
    topY:SetHeight(16)
    topY:SetPoint("TOPLEFT", tl, "TOPRIGHT")
    topY:SetPoint("TOPRIGHT", tr, "TOPLEFT")
    skinData.sbBackdrop, skinData.sbFill = edge, fillTex
    skinData.sbRims = { tl, bl, tr, br, leftX, right, bottom, topY }
    if CHAT.SB_SyncBackdrop then
        CHAT.SB_SyncBackdrop(true)
    end
end

-- The backdrop in the SELECTED window's stored colour and opacity (what
-- Blizzard paints its own column in); memoised, a secret read skips.
function CHAT._SB_SyncBackdropImpl(force)
    local cf1 = _G.ChatFrame1
    local skinData = cf1 and CFD(cf1)
    local fillTex = skinData and skinData.sbFill
    if not fillTex then
        return
    end
    -- Hidden (Hide Sidebar Background): nothing to paint; showing it again
    -- forces a sync.
    if not force and not skinData.sbBackdrop:IsShown() then
        return
    end
    local ident = 1
    local sel = GENERAL_CHAT_DOCK
        and FCFDock_GetSelectedWindow
        and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
    local cc = Constants and Constants.ChatFrameConstants
    local spellRef = sel and sel.GetID and sel:GetID()
    if spellRef and spellRef >= 1 and spellRef <= ((cc and cc.MaxChatWindows) or 10) then
        ident = spellRef
    end
    if not GetChatWindowInfo then
        return
    end
    local _, _, red, green, blue, a = GetChatWindowInfo(ident)
    if type(a) ~= "number" or (issecretvalue and (issecretvalue(red) or issecretvalue(a))) then
        return
    end
    local m = CHAT._sbBdMemo
    if not force and m[1] == red and m[2] == green and m[3] == blue and m[4] == a then
        return
    end
    m[1], m[2], m[3], m[4] = red, green, blue, a
    fillTex:SetColorTexture(red, green, blue, a)
    local rims = skinData.sbRims
    for index = 1, #rims do
        rims[index]:SetVertexColor(red, green, blue, a)
    end
end

-- Pressed glyph: Blizzard's (-1,-2) at 0.75 (vanilla -Down art moves the
-- glyph the same way). Shared functions on our buttons, no closures.
-- _sbGYs = a kit glyph's own lift at the current Icon Size (nil = centred).
function CHAT.SB_GlyphDown(self, btnFrame)
    if btnFrame and btnFrame ~= "LeftButton" then
        return
    end
    local ic = self._icon
    if ic and self._sbGlyph then
        self._sbPushed = true
        ic:ClearAllPoints()
        ic:SetPoint("CENTER", self, "CENTER", -1, -2 + (self._sbGYs or 0))
        ic:SetAlpha(0.75)
    end
end
-- Also on OnHide (a press can end off the button): only a pressed glyph has
-- anything to put back.
function CHAT.SB_GlyphUp(self)
    if not self._sbPushed then
        return
    end
    self._sbPushed = nil
    local ic = self._icon
    if ic and self._sbGlyph then
        ic:ClearAllPoints()
        ic:SetPoint("CENTER", self, "CENTER", 0, self._sbGYs or 0)
        ic:SetAlpha(1)
    end
end
-- The gear's states follow Blizzard's own order (pressed-hover, hover,
-- pressed, idle).
function CHAT.SB_GearPaint(self)
    local ic = self._icon
    if not ic then
        return
    end
    local a = (self._sbDown and self._sbOver and GEAR.both)
        or (self._sbOver and GEAR.over)
        or (self._sbDown and GEAR.down)
        or GEAR.idle
    if self._sbGearArt ~= a then
        self._sbGearArt = a
        ic:SetAtlas(a)
    end
end
function CHAT.SB_GearEnter(self)
    self._sbOver = true
    CHAT.SB_GearPaint(self)
end
function CHAT.SB_GearLeave(self)
    self._sbOver = nil
    CHAT.SB_GearPaint(self)
end
function CHAT.SB_GearDown(self, btnFrame)
    if btnFrame and btnFrame ~= "LeftButton" then
        return
    end
    self._sbDown = true
    CHAT.SB_GearPaint(self)
end
function CHAT.SB_GearUp(self)
    self._sbDown = nil
    CHAT.SB_GearPaint(self)
end

-- Dress one of our sidebar buttons with the kit's entry for `key`.
function CHAT.SB_Dress(button, key)
    local kit = CHAT.SB_KIT
    local e = kit and kit[key]
    if not e then
        return
    end
    if e.withChatMenu and CHAT.SB_ChatMenuOn then
        e = e.withChatMenu
    end
    if e.gear and not CHAT.SB_ArtOK(GEAR_PROBE) then
        e = e.alt
    end
    button._sbEntry = e
    button._sbKey = key
    button._sbTailInside = (e.count == "inside") or nil
    local iconTex = button._icon
    if e.gear then
        iconTex:SetDrawLayer("ARTWORK")
        iconTex:ClearAllPoints()
        iconTex:SetAllPoints(button)
        iconTex:SetDesaturated(false)
        iconTex:SetVertexColor(1, 1, 1, 1)
        CHAT.SB_GearPaint(button)
        button:HookScript("OnEnter", CHAT.SB_GearEnter)
        button:HookScript("OnLeave", CHAT.SB_GearLeave)
        button:HookScript("OnMouseDown", CHAT.SB_GearDown)
        button:HookScript("OnMouseUp", CHAT.SB_GearUp)
        button:HookScript("OnHide", CHAT.SB_GearUp)
        return
    end
    SetStateArt(button, "Normal", Pick(e.n))
    SetStateArt(button, "Pushed", Pick(e.p))
    SetStateArt(button, "Highlight", Pick(e.hl), e.hlBlend)
    -- WoW Forever: the kit's bronze plate under the glyph (our frames).
    if e.plate then
        CHAT.FV_Plate(button, true)
    end
    if e.inset then
        local tex = button:CreateTexture(nil, "BACKGROUND")
        tex:SetColorTexture(0, 0, 0, e.inset)
        button._sbInset = tex
    end
    local g
    if e.glyph then
        for index = 1, #e.glyph do
            if CHAT.SB_ArtOK(e.glyph[index]) then
                g = e.glyph[index]
                break
            end
        end
    end
    if g then
        iconTex:SetDrawLayer("OVERLAY")
        iconTex:ClearAllPoints()
        iconTex:SetPoint("CENTER", button, "CENTER", 0, g.y or 0)
        iconTex:SetDesaturated(false)
        if g.atlas then
            iconTex:SetAtlas(g.atlas)
        else
            iconTex:SetTexture(g.file)
            local tc = g.tc
            if tc then
                iconTex:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
            else
                iconTex:SetTexCoord(0, 1, 0, 1)
            end
        end
        -- A kit tint (WoW Forever's tan; a glyph may carry its own) wins
        -- over the gold/white glyph rule.
        local tint = g.tint or kit.tint
        if tint then
            iconTex:SetDesaturated(true)
            iconTex:SetVertexColor(tint[1], tint[2], tint[3], 1)
        elseif g.gold then
            iconTex:SetVertexColor(GOLD_R, GOLD_G, GOLD_B, 1)
        else
            iconTex:SetVertexColor(1, 1, 1, 1)
        end
        button._sbGW, button._sbGH = g.w, g.h
        button._sbGY, button._sbGYs = g.y, g.y
        iconTex:Show()
        if e.push then
            button._sbGlyph = true
            button:HookScript("OnMouseDown", CHAT.SB_GlyphDown)
            button:HookScript("OnMouseUp", CHAT.SB_GlyphUp)
            button:HookScript("OnHide", CHAT.SB_GlyphUp)
        end
    else
        iconTex:Hide()
    end
end

-- Scroll-to-bottom button: the art the stock UI shows in that seat, plus the
-- scrolled-back flash (a copy of the art, ADD, animated only while the
-- selected window is scrolled back). Re-run on every seat change.
function CHAT.SB_DressScroll(button, seat)
    local kit = CHAT.SB_KIT
    local e = kit and kit.scroll and kit.scroll[seat]
    if not e then
        return
    end
    button._sbEntry = e
    if button._icon then
        button._icon:Hide()
    end
    SetStateArt(button, "Normal", Pick(e.n))
    SetStateArt(button, "Pushed", Pick(e.p))
    SetStateArt(button, "Highlight", Pick(e.hl), e.hlBlend)
    -- WoW Forever: the bronze plate and a tinted glyph in the sidebar seat
    -- (re-run on every seat change; the chat seat wears plain art, which a
    -- move back to the plate clears).
    if e.plate or button._fvPlate then
        CHAT.FV_Plate(button, e.plate == true)
    end
    if e.plate and button.ClearNormalTexture then
        button:ClearNormalTexture()
        button:ClearPushedTexture()
        button:ClearHighlightTexture()
    end
    local g = e.glyph and e.glyph[1]
    if g and button._icon and CHAT.SB_ArtOK(g) then
        local ic, tint = button._icon, g.tint or kit.tint
        ic:SetDrawLayer("OVERLAY")
        ic:ClearAllPoints()
        ic:SetPoint("CENTER", button, "CENTER", 0, 0)
        ic:SetAtlas(g.atlas)
        ic:SetDesaturated(tint ~= nil)
        if tint then
            ic:SetVertexColor(tint[1], tint[2], tint[3], 1)
        else
            ic:SetVertexColor(1, 1, 1, 1)
        end
        button._sbGW, button._sbGH = g.w, g.h
        ic:Show()
    elseif button._sbGW then
        button._sbGW, button._sbGH = nil, nil
    end
    local fl = button._sbFlash
    if not fl then
        fl = button:CreateTexture(nil, "OVERLAY")
        fl:SetAllPoints(button)
        fl:SetAlpha(0)
        fl:Hide()
        local anim = fl:CreateAnimationGroup()
        anim:SetLooping("REPEAT")
        local function Step(sequence, from, to, dur)
            local fade = anim:CreateAnimation("Alpha")
            fade:SetFromAlpha(from)
            fade:SetToAlpha(to)
            fade:SetDuration(dur)
            fade:SetOrder(sequence)
        end
        if kit.flash == "blink" then
            -- Vanilla: hard on for half a second, off for half a second.
            Step(1, 1, 1, 0.5)
            Step(2, 0, 0, 0.5)
        else
            -- Retail: 0.1s in, 0.5s held, 0.1s out, 0.5s off.
            Step(1, 0, 1, 0.1)
            Step(2, 1, 1, 0.5)
            Step(3, 1, 0, 0.1)
            Step(4, 0, 0, 0.5)
        end
        button._sbFlash, button._sbFlashAG = fl, anim
    end
    local fa = Pick(e.flashArt)
    if fa then
        if fa.atlas then
            fl:SetAtlas(fa.atlas)
        else
            fl:SetTexture(fa.file)
        end
        fl:SetBlendMode("ADD")
    end
    -- A glyph seat flashes the glyph itself; a plain seat the whole button.
    local onIcon = button._sbGW ~= nil
    if (button._sbFlOnIcon or false) ~= onIcon then
        button._sbFlOnIcon = onIcon
        fl:ClearAllPoints()
        fl:SetAllPoints(onIcon and button._icon or button)
    end
end

-- A count under its button, or inside it (the QuickJoin plate), in the
-- Fonts-page chat font with the house shadow. Always a region of its own
-- button, which sits above the Blizzard Style backdrop (a region of the
-- sidebar itself would share the backdrop's frame level and can draw under
-- its fill).
function CHAT.SB_MakeCount(button, sidebar, key)
    local e = button._sbEntry
    local inside = e and e.count == "inside"
    local fontStr = button:CreateFontString(nil, "OVERLAY")
    CUI.PrimeFontShadow(fontStr, true)
    fontStr:SetFont(CHAT.GetFont(), 10, "")
    -- A kit count colour (WoW Forever's tan), else white.
    local cc = CHAT.SB_KIT and CHAT.SB_KIT.countColor
    if cc then
        fontStr:SetTextColor(cc[1], cc[2], cc[3], 1)
    else
        fontStr:SetTextColor(1, 1, 1, 1)
    end
    if inside then
        fontStr:SetPoint("BOTTOM", button, "BOTTOM", 0, (CHAT.SB_KIT and CHAT.SB_KIT.countY) or 4)
    else
        -- Right under the VISIBLE art: the button's transparent bottom rows
        -- come off (re-anchored with Icon Size in SB_ApplyScale).
        fontStr:SetPoint("TOP", button, "BOTTOM", 0, (e and e.padB) or 0)
    end
    fontStr._sbInside = inside or nil
    return fontStr
end

-- Sizes, pads and free-move heights from the kit and Icon Size (constants,
-- never a geometry read). The build call (force) only stamps; a slider change
-- re-runs the chain (through the width pass when the width follows Icon Size).
local COUNT_REF = { "friendsCount", "guildCount", "durabilityPct" }
local COUNT_OWNER = { friendsCount = "friendsBtn", guildCount = "guildBtn", durabilityPct = "durabilityBtn" }
function CHAT.SB_ApplyScale(skinData, s, force)
    -- Memo inputs: the scale and the count font (a profile swap can change
    -- the font alone).
    local font = CHAT.GetFont()
    local rescaled = skinData._sbScale ~= s
    if not force and not rescaled and skinData._sbFont == font then
        return
    end
    skinData._sbScale, skinData._sbFont = s, font
    for _, ref in pairs(CHAT.SB_REF) do
        local button = skinData[ref]
        local e = button and button._sbEntry
        if e then
            button:SetSize(e.w * s, e.h * s)
            button._freeMoveH = e.h * s
            button._sbPadT = (e.padT or 0) * s
            button._sbPadB = (e.padB or 0) * s
            if button._sbGW and button._icon then
                button._icon:SetSize(button._sbGW * s, button._sbGH * s)
            end
            -- A lifted kit glyph keeps its lift in step with Icon Size.
            if button._sbGY and button._icon then
                button._sbGYs = button._sbGY * s
                if not button._sbPushed then
                    button._icon:ClearAllPoints()
                    button._icon:SetPoint("CENTER", button, "CENTER", 0, button._sbGYs)
                end
            end
            local ins = button._sbInset
            if ins then
                ins:ClearAllPoints()
                ins:SetPoint("TOPLEFT", button, "TOPLEFT", 5 * s, -6 * s)
                ins:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -6 * s, 6 * s)
            end
        end
    end
    local fsz = math.max(7, 10 * s)
    for index = 1, #COUNT_REF do
        local fontStr = skinData[COUNT_REF[index]]
        if fontStr then
            CUI.PrimeFontShadow(fontStr, true)
            fontStr:SetFont(font, fsz, "")
            fontStr._freeMoveH = fsz
            local ownerFrame = skinData[COUNT_OWNER[COUNT_REF[index]]]
            if ownerFrame then
                fontStr:ClearAllPoints()
                if fontStr._sbInside then
                    fontStr:SetPoint(
                        "BOTTOM",
                        ownerFrame,
                        "BOTTOM",
                        0,
                        ((CHAT.SB_KIT and CHAT.SB_KIT.countY) or 4) * s
                    )
                else
                    fontStr:SetPoint("TOP", ownerFrame, "BOTTOM", 0, ownerFrame._sbPadB or 0)
                end
            end
        end
    end
    local sbtn = skinData.scrollBtn
    local se = sbtn and sbtn._sbEntry
    if se then
        sbtn:SetSize(se.w * s, se.h * s)
        sbtn._freeMoveH = se.h * s
        -- A glyph seat (WoW Forever's sidebar seat) sizes its glyph too.
        if sbtn._sbGW and sbtn._icon then
            sbtn._icon:SetSize(sbtn._sbGW * s, sbtn._sbGH * s)
        end
    end
    -- A font-only change re-fonts the counts and stops; a new scale re-runs
    -- the chain once (the width pass already reaches ApplySidebarIcons).
    if force or not rescaled then
        return
    end
    if CHAT.DB().sidebarWidth == nil and CHAT.ApplySidebarWidth then
        CHAT.ApplySidebarWidth()
    elseif CHAT.ApplySidebarIcons then
        CHAT.ApplySidebarIcons()
    end
end

-- Durability doll tint from the worst equipment alert (0 fine, 1 damaged,
-- 2 broken); paints on change only.
function CHAT.SB_DurabilityAlert(button)
    if not (button and button._icon and GetInventoryAlertStatus) then
        return
    end
    local worst = 0
    for index = 1, 11 do
        local st = GetInventoryAlertStatus(index)
        if type(st) == "number" and not (issecretvalue and issecretvalue(st)) and st > worst then
            worst = st
        end
    end
    if worst > 2 then
        worst = 2
    end
    if button._sbAlert == worst then
        return
    end
    button._sbAlert = worst
    local e = button._sbEntry
    local color = ((e and e.alertColors) or CHAT.SB_ALERT)[worst]
    button._icon:SetVertexColor(color[1], color[2], color[3], color[4])
end

-- Blizzard Style voice button: the headset while a voice channel is active,
-- the voice-chat icon otherwise (Blizzard's own two events).
function CHAT.SB_PaintVoice()
    local button = CHAT._sbVoiceBtn
    if not (button and button._icon and button._sbGW) then
        return
    end
    local enabled = C_VoiceChat and C_VoiceChat.GetActiveChannelID and C_VoiceChat.GetActiveChannelID() ~= nil
        or false
    if button._sbVoiceOn == enabled then
        return
    end
    button._sbVoiceOn = enabled
    button._icon:SetAtlas(enabled and "chatframe-button-icon-headset" or "chatframe-button-icon-voicechat")
end
function CHAT.SB_WatchVoice(button)
    CHAT._sbVoiceBtn = button
    if not CHAT._sbVoiceEvents then
        local frame = CreateFrame("Frame")
        frame:RegisterEvent("VOICE_CHAT_CHANNEL_ACTIVATED")
        frame:RegisterEvent("VOICE_CHAT_CHANNEL_DEACTIVATED")
        frame:SetScript("OnEvent", CHAT.SB_PaintVoice)
        CHAT._sbVoiceEvents = frame
    end
    CHAT.SB_PaintVoice()
end

-- The scroll button flashes while the selected window is scrolled back:
-- started and stopped on the engine's own scrollbar edges and on a selection
-- change, the animation itself runs in C.
function CHAT._SB_FlashSyncImpl()
    local cf1 = _G.ChatFrame1
    local skinData = cf1 and CFD(cf1)
    local button = skinData and skinData.scrollBtn
    local fl, ag = button and button._sbFlash, button and button._sbFlashAG
    if not (fl and ag) then
        return
    end
    local sel = (
        GENERAL_CHAT_DOCK
        and FCFDock_GetSelectedWindow
        and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
    ) or cf1
    local enabled = (CHAT.EngineIsScrolled and CHAT.EngineIsScrolled(sel)) and true or false
    if button._sbFlashing == enabled then
        return
    end
    button._sbFlashing = enabled
    if enabled then
        fl:Show()
        ag:Play()
    else
        ag:Stop()
        fl:SetAlpha(0)
        fl:Hide()
    end
end
