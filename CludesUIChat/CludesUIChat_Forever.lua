if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIChat_Forever.lua
--
--  The chat under WoW Forever (the Forever client's variant of Blizzard
--  Style, ns.ChatForever). Blizzard's chat frame art and input art are
--  stripped as on the CludesUI look, and the Forever bronze kit is drawn
--  on OUR frames only:
--    - the panel (CFD(cf).bg): a message frame and an input frame
--    - the ghost tabs (CludesUIChat_Tabs.lua): bronze tabs, warm while
--      selected
--    - the sidebar buttons: square bronze plates with tan glyphs (a kit for
--      CludesUIChat_SidebarStock.lua)
--  Every piece is framed by the bronze line of Forever's micro menu box
--  (CludesUI.ForeverBorder: that art cut hollow, at its own size) over our
--  own fill; the selected tab and a hovered plate add an additive copy that
--  warms the line toward copper. The variant latch asks for that frame: a
--  client that cannot draw it renders plain Blizzard Style.
--  The Border Style (ns.ChatFvKind, latched with the look) picks the frame:
--  Slim draws the line from our shipped flat art, Slim Textured from
--  Blizzard's live art (the line and its copper copies alike), and Heavy
--  Bronze frames every piece in the bronze frame of Forever's own windows
--  instead (CludesUI.ForeverHeavy, on an art host at the piece's scale),
--  its copper copy on the selected tab and a hovered plate.
--
--  At load this file only defines data and functions: nothing is built,
--  registered or hooked off the variant (every caller tests the latch).
-------------------------------------------------------------------------------
local _, mod = ...
local CUI = _G.CludesUI
local CHAT = mod.ECHAT
if not CHAT or not CUI then
    return
end
local CFD = CUI._chatCFD
local BORDER = CUI.FOREVER_BORDER
local HEAVY = CUI.FOREVER_HEAVY

local FV = {
    lift = { 1, 0.75, 0.45, 0.6 }, -- the additive copy: tint, alpha
    -- Heavy Bronze: the art scale per piece (its rim and dark line are
    -- HEAVY.band art units; the panel at the window scale) and each tab's
    -- art pulled in from Blizzard's 1px tab gap.
    panelK = HEAVY.k,
    tabK = 0.8,
    btnK = 0.7,
    hvTabInset = 1,
    -- Panel geometry off the chat frame's rect (UI units): both frames' outer
    -- edges X past its sides (the text stands well clear of the line) and
    -- TOP above it (Blizzard's tab row stands there), the message frame
    -- MSG_B under the text, a GAP, then the input frame with IN_PAD round
    -- the edit box, whose sides sit EB_X past the text's (its chat-type
    -- header, 15 into the box, lands on the text column). The combat log's
    -- filter bar (CL_BAR tall, above its window) sits inside that window's
    -- frame.
    X = 20,
    TOP = 3,
    MSG_B = 11,
    GAP = 4,
    IN_PAD = 5,
    EB_X = 15,
    CL_BAR = 24,
    -- Each tab's line in from its ghost's sides and top by its outer
    -- shadow's reach, so the ghost's clip keeps that shadow.
    tabInset = BORDER.outer,
    tabX = 8, -- the first docked tab's left edge in from the panel's
    gold = { 1, 0.82, 0 },
    tan = { 0.83, 0.71, 0.52 },
    thumb = { 0.72, 0.56, 0.36, 0.7 },
    plateFill = { 0.06, 0.06, 0.065, 0.92 },
    -- Tab bodies, bottom then top: selected (warm) and idle.
    tabSel = { 0.17, 0.09, 0.035, 0.95, 0.12, 0.063, 0.024, 0.95 },
    tabIdle = { 0.08, 0.08, 0.085, 0.92, 0.10, 0.10, 0.105, 0.92 },
    -- The last fill ApplyBackground painted (panels built later take it).
    _fill = { r = 0.03, g = 0.045, b = 0.05, a = 0.65 },
}
CHAT.FV = FV

-------------------------------------------------------------------------------
--  Framed box: the line and the body fill under it, on an art host of ours.
--  The line's art is the latched Border Style's (shipped or Blizzard's live
--  art; ForeverBorder reads "textured" as the live one).
-------------------------------------------------------------------------------
local function NewBox(owner)
    local box = { host = owner }
    box.fill = owner:CreateTexture(nil, "BACKGROUND")
    box.rim = CUI.ForeverBorder(owner, "BORDER", 0, nil, mod.ChatFvKind())
    return box
end

local function Seat(t, owner, tp, x1, y1, x2, y2)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", owner, tp, x1, y1)
    t:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", x2, y2)
end

-- The line's outer edge on the host's sides (pulled in by inX), its top ty
-- off the host point tp (TOPLEFT or BOTTOMLEFT) and its bottom by above the
-- host's bottom; the fill FOREVER_BORDER.fill in from that edge (its
-- corners inside the chamfers).
local function SeatBox(box, owner, tp, ty, by, inX)
    local frame, posX = BORDER.fill, inX or 0
    local s = box.seat
    if not s then
        s = {}
        box.seat = s
    end
    s[1], s[2], s[3], s[4], s[5] = tp, posX, ty, -posX, by
    CUI.ForeverBorderSeat(box.rim, owner, tp, posX, ty, -posX, by)
    if box.lift then
        CUI.ForeverBorderSeat(box.lift, owner, tp, posX, ty, -posX, by)
    end
    Seat(box.fill, owner, tp, posX + frame, ty - frame, -posX - frame, by + frame)
end

-- Heavy Bronze: the frame and the body fill under it, on an art host drawn
-- at the piece's scale; with `lift` also its copper copy (a highlight),
-- hidden until shown.
local function NewHeavyBox(owner, lift)
    local box = { host = owner, heavy = true }
    box.fill = owner:CreateTexture(nil, "BACKGROUND")
    box.rim = CUI.ForeverHeavy(owner, "BORDER")
    if lift then
        local l = HEAVY.lift
        box.lift = CUI.ForeverHeavy(owner, "ARTWORK", 0, true)
        CUI.ForeverHeavyPaint(box.lift, l[1], l[2], l[3], l[4])
        CUI.ForeverHeavyShown(box.lift, false)
    end
    return box
end

-- The rim's outer edge as SeatBox places the line's (UI units); the fill
-- FOREVER_HEAVY.fill in from it, under the rim.
local function SeatHeavyBox(box, owner, tp, ty, by, inX)
    local posX = inX or 0
    CUI.ForeverHeavySeat(box.rim, owner, tp, posX, ty, -posX, by)
    if box.lift then
        CUI.ForeverHeavySeat(box.lift, owner, tp, posX, ty, -posX, by)
    end
    CUI.ForeverHeavyFill(box.rim, box.fill, owner, tp, posX, ty, -posX, by)
end

-- The line's copper copy over it (the selected tab, a hovered plate), built
-- the first time it shows, on the line's seat, from the line's own art.
local function ShowLift(box, isShown)
    local lift = box.lift
    if not lift then
        if not isShown then
            return
        end
        local l, s = FV.lift, box.seat
        lift = CUI.ForeverBorder(box.host, "ARTWORK", 0, true, mod.ChatFvKind())
        CUI.ForeverBorderPaint(lift, l[1], l[2], l[3], l[4])
        CUI.ForeverBorderSeat(lift, box.host, s[1], s[2], s[3], s[4], s[5])
        box.lift = lift
    end
    CUI.ForeverBorderShown(lift, isShown)
end

local function PaintFill(t, texture, region, g, b, a)
    if texture then
        t:SetTexture(texture)
        t:SetVertexColor(region, g, b, a)
    else
        t:SetVertexColor(1, 1, 1, 1)
        t:SetColorTexture(region, g, b, a)
    end
end

-------------------------------------------------------------------------------
--  Panel: the message frame round the text and the input frame round the
--  edit box, on one art host that covers our panel (never a Blizzard frame).
-------------------------------------------------------------------------------
-- How far the panel reaches under the chat frame's rect.
function CHAT.FV_PanelDrop(inputH)
    return FV.MSG_B + FV.GAP + 2 * FV.IN_PAD + inputH
end

-- The edit box in the input frame: the same plain setters the CludesUI
-- look uses (every window, temporary ones included; no hooks here).
function CHAT.FV_PlaceEditBox(castFrame, eb, inputH)
    local posY = -(FV.MSG_B + FV.GAP + FV.IN_PAD)
    eb:ClearAllPoints()
    eb:SetPoint("TOPLEFT", castFrame, "BOTTOMLEFT", -FV.EB_X, posY)
    eb:SetPoint("TOPRIGHT", castFrame, "BOTTOMRIGHT", FV.EB_X, posY)
    eb:SetHeight(inputH)
end

-- Seats the input and records the panel insets (numeric placement off the
-- chat frame's rect, PositionChatPanel; the engine derives the text area).
function CHAT.FV_SeatInput(castFrame, eb, inputH)
    if eb then
        CHAT.FV_PlaceEditBox(castFrame, eb, inputH)
    end
    local skinData = CFD(castFrame)
    local ins = skinData._bgIns
    if not ins then
        ins = {}
        skinData._bgIns = ins
    end
    ins.l, ins.r = -FV.X, FV.X
    ins.t = FV.TOP + ((castFrame == _G.ChatFrame2) and FV.CL_BAR or 0)
    ins.b = -CHAT.FV_PanelDrop(inputH)
    CHAT.FV_LayoutPanel(castFrame, inputH)
end

-- Both boxes off the panel's edges; re-seated only when the input height
-- changes.
function CHAT.FV_LayoutPanel(castFrame, inputH)
    local skinData = CFD(castFrame)
    local owner = skinData.fvHost
    if not owner or skinData.fvInputH == inputH then
        return
    end
    skinData.fvInputH = inputH
    local inTall = inputH + 2 * FV.IN_PAD
    if skinData.fvMsg.heavy then
        SeatHeavyBox(skinData.fvMsg, owner, "TOPLEFT", 0, inTall + FV.GAP)
        SeatHeavyBox(skinData.fvIn, owner, "BOTTOMLEFT", inTall, 0)
        return
    end
    SeatBox(skinData.fvMsg, owner, "TOPLEFT", 0, inTall + FV.GAP)
    SeatBox(skinData.fvIn, owner, "BOTTOMLEFT", inTall, 0)
end

-- Built once per panel, at its creation. The host sits one level over the
-- panel, under our message frame (panel + 4); Heavy Bronze draws it at the
-- panel's art scale.
function CHAT.FV_BuildPanel(castFrame, backdrop, inputH)
    local skinData = CFD(castFrame)
    if skinData.fvHost then
        return
    end
    local owner = CreateFrame("Frame", nil, backdrop)
    local New = NewBox
    if mod.ChatFvHeavy() then
        owner:SetScale(FV.panelK)
        New = NewHeavyBox
    end
    owner:SetAllPoints(backdrop)
    skinData.fvHost = owner
    skinData.fvMsg, skinData.fvIn = New(owner), New(owner)
    CHAT.FV_LayoutPanel(castFrame, inputH)
    local p = FV._fill
    PaintFill(skinData.fvMsg.fill, p.tex, p.r, p.g, p.b, p.a)
    PaintFill(skinData.fvIn.fill, p.tex, p.r, p.g, p.b, p.a)
end

-- The chat background colour/texture (Chat page) fills both boxes.
function CHAT.FV_PaintFills(texture, region, g, b, a)
    local p = FV._fill
    p.tex, p.r, p.g, p.b, p.a = texture, region, g, b, a
    for index = 1, 20 do
        local castFrame = _G["ChatFrame" .. index]
        local skinData = castFrame and CFD(castFrame)
        if skinData and skinData.fvHost then
            PaintFill(skinData.fvMsg.fill, texture, region, g, b, a)
            PaintFill(skinData.fvIn.fill, texture, region, g, b, a)
        end
    end
end

-------------------------------------------------------------------------------
--  Tabs: each ghost wears a bronze tab whose bottom line and lower chamfers
--  run under the panel's top edge and are clipped away, so its sides meet
--  the message frame's line (Heavy Bronze: its bottom rim and inner shadow,
--  meeting the frame's rim). Built once per ghost; repainted only when its
--  selected state flips.
-------------------------------------------------------------------------------
local tabCol -- colour objects (selected bottom, top, idle bottom, top)
local function TabColours()
    local s, index = FV.tabSel, FV.tabIdle
    tabCol = {
        CreateColor(s[1], s[2], s[3], s[4]),
        CreateColor(s[5], s[6], s[7], s[8]),
        CreateColor(index[1], index[2], index[3], index[4]),
        CreateColor(index[5], index[6], index[7], index[8]),
    }
end

function CHAT.FV_StyleGhost(g, isActive)
    local art = g._fvArt
    if not art then
        local clip = CreateFrame("Frame", nil, g)
        clip:SetAllPoints(g)
        clip:SetClipsChildren(true)
        art = CreateFrame("Frame", nil, clip)
        local heavy = mod.ChatFvHeavy()
        if heavy then
            art:SetScale(FV.tabK)
        end
        art:SetAllPoints(clip)
        -- Label and alert glow over the art (they are the ghost's regions).
        local topY = CreateFrame("Frame", nil, g)
        topY:SetAllPoints(g)
        g._fs:SetParent(topY)
        g._glow:SetParent(topY)
        local box
        if heavy then
            -- The selected tab's rim reads warmer than the panel's (its
            -- copper copy, shown only while selected).
            box = NewHeavyBox(art, true)
            box.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
            -- The bottom rim and its inner shadow run under the ghost, where
            -- the clip takes them.
            SeatHeavyBox(box, art, "TOPLEFT", 0, -HEAVY.shade * FV.tabK, FV.hvTabInset)
        else
            -- The selected tab's line reads warmer than the panel's (the
            -- lift, shown only while selected).
            box = NewBox(art)
            box.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
            -- The bottom line sits the corners' reach under the ghost, so the
            -- clip takes it and both lower chamfers: the sides run straight
            -- down to the ghost's bottom edge.
            SeatBox(box, art, "TOPLEFT", -FV.tabInset, -BORDER.corner, FV.tabInset)
        end
        g._fvClip, g._fvArt, g._fvTop, g._fvBox = clip, art, topY, box
        g._bg:Hide()
        g._underline:Hide()
        g._sep:Hide()
        g._borderHost:Hide()
        if not tabCol then
            TabColours()
        end
    end
    -- Relative levels, re-asserted: docked ghosts change parent between
    -- passes (strip / scroll clip).
    local L = g:GetFrameLevel()
    if g._fvClip:GetFrameLevel() ~= L + 1 then
        g._fvClip:SetFrameLevel(L + 1)
    end
    if art:GetFrameLevel() ~= L + 2 then
        art:SetFrameLevel(L + 2)
    end
    if g._fvTop:GetFrameLevel() ~= L + 3 then
        g._fvTop:SetFrameLevel(L + 3)
    end
    if g._fvOn == isActive then
        return
    end
    g._fvOn = isActive
    local box = g._fvBox
    local val = isActive and 1 or 0.85
    if box.heavy then
        CUI.ForeverHeavyPaint(box.rim, val, val, val, 1, not isActive)
        CUI.ForeverHeavyShown(box.lift, isActive)
    else
        CUI.ForeverBorderPaint(box.rim, val, val, val, 1, not isActive)
        ShowLift(box, isActive)
    end
    if isActive then
        box.fill:SetGradient("VERTICAL", tabCol[1], tabCol[2])
    else
        box.fill:SetGradient("VERTICAL", tabCol[3], tabCol[4])
    end
end

-------------------------------------------------------------------------------
--  Sidebar plates: the square bronze button under a sidebar button's own
--  regions (glyph, count), its line warmed on hover (Heavy Bronze: the
--  bronze frame, its copper copy on hover). `on` false hides it (the scroll
--  button's chat seat wears plain art).
-------------------------------------------------------------------------------
local function PlateEnter(self)
    local p = self._fvPlate
    if p then
        ShowLift(p, true)
    end
end
local function PlateLeave(self)
    local p = self._fvPlate
    if p then
        ShowLift(p, false)
    end
end
local function HeavyPlateEnter(self)
    local p = self._fvPlate
    if p then
        CUI.ForeverHeavyShown(p.lift, true)
    end
end
local function HeavyPlateLeave(self)
    local p = self._fvPlate
    if p then
        CUI.ForeverHeavyShown(p.lift, false)
    end
end

function CHAT.FV_Plate(button, enabled)
    local p = button._fvPlate
    if not p then
        if not enabled then
            return
        end
        local owner = CreateFrame("Frame", nil, button)
        local heavy = mod.ChatFvHeavy()
        if heavy then
            owner:SetScale(FV.btnK)
        end
        owner:SetAllPoints(button)
        p = heavy and NewHeavyBox(owner, true) or NewBox(owner)
        local c = FV.plateFill
        p.fill:SetColorTexture(c[1], c[2], c[3], c[4])
        if heavy then
            SeatHeavyBox(p, owner, "TOPLEFT", 0, 0)
        else
            SeatBox(p, owner, "TOPLEFT", 0, 0)
        end
        button._fvPlate = p
        button:HookScript("OnEnter", heavy and HeavyPlateEnter or PlateEnter)
        button:HookScript("OnLeave", heavy and HeavyPlateLeave or PlateLeave)
    end
    -- One level under the button (re-asserted: the scroll button changes
    -- level with its seat).
    local L = button:GetFrameLevel()
    local wanted = L > 0 and L - 1 or 0
    if p.host:GetFrameLevel() ~= wanted then
        p.host:SetFrameLevel(wanted)
    end
    p.host:SetShown(enabled and true or false)
    return p
end

-------------------------------------------------------------------------------
--  Sidebar kit (read by ECHAT.SB_Latch under the variant): bronze plates,
--  Blizzard's glyphs where it has them and ours elsewhere, all in tan; the
--  column stands GAP clear of the panel's left edge (the same gap as
--  between the panel's two frames), level with its top.
--  Built on the Forever client only (the latch nil-guards the kit).
-------------------------------------------------------------------------------
local Entry = CHAT.SB_Entry
if CUI.IS_FOREVER and Entry and CHAT.SB_KITS then
    local MEDIA = "Interface\\AddOns\\CludesUIChat\\Media\\"
    local TAN = FV.tan
    -- Blizzard's atlas glyphs desaturate darker than our white PNG ink: a
    -- brighter tint (tan / 0.83) lands them on the same tan.
    local ATL_TINT = { 1, 0.86, 0.63 }
    local FSQ = { w = 34, h = 34, padT = 0, padB = 0, plate = true, push = true }
    local function A(atlas, wid, hgt, posY)
        return { atlas = atlas, w = wid, h = hgt, y = posY, tint = ATL_TINT }
    end
    local function P(name, posY)
        return { file = MEDIA .. name, w = 18, h = 18, y = posY }
    end
    local blizz = CHAT.SB_KITS.blizzard
    CHAT.SB_KITS.forever = {
        col = { dx = -FV.GAP, top = 0, bot = 0 },
        colW = 34,
        gap = 8,
        voiceState = true,
        flash = "fade",
        tint = TAN,
        countColor = TAN,
        countY = 5,
        friends = Entry(FSQ, {
            count = "inside",
            glyph = {
                A("socialqueuing-icon-group", 20, 17, 5),
                P("chat_friends.png", 5),
            },
        }),
        guild = Entry(FSQ, {
            count = "below",
            glyph = {
                A("friends-icon-tab-guildmates", 17, 17),
                P("chat_guild.png"),
            },
        }),
        durability = Entry(FSQ, {
            count = "inside",
            alert = true,
            glyph = { P("chat_durability.png", 5) },
            alertColors = {
                [0] = { TAN[1], TAN[2], TAN[3], 1 },
                { 1, 0.5, 0.1, 1 },
                { 0.93, 0.07, 0.07, 1 },
            },
        }),
        copy = Entry(FSQ, { glyph = { P("chat_copy.png") } }),
        portals = Entry(FSQ, { glyph = { P("chat_portal.png") } }),
        voice = Entry(FSQ, { glyph = { A("chatframe-button-icon-voicechat", 20, 20) } }),
        chatmenu = Entry(FSQ, { glyph = { { file = CHAT.CHAT_MENU_GLYPH, w = 18, h = 18 } } }),
        settings = Entry(FSQ, { glyph = { P("chat_settings.png") } }),
        scroll = {
            sidebar = {
                w = 34,
                h = 34,
                plate = true,
                glyph = { A("minimal-scrollbar-arrow-returntobottom", 17, 15) },
                flashArt = { atlas = "minimal-scrollbar-arrow-returntobottom" },
            },
            chat = blizz and blizz.scroll and blizz.scroll.chat,
        },
    }
end
