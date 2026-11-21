if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_RaidFrames_TextPaint.lua
--
--  The texts of a raid frame (CUI_RaidFrames_TextKeys.lua) on live buttons: a
--  text plan per settings source, one FontString per text built on first need,
--  its font, anchor and colour, and one painter per kind. The event paths read
--  the plan and settings the button was last painted with (d._txP, d._txS).
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIRaidFrames.lua or an earlier Raid Frames file failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local pairs, setmetatable, type, CreateFrame = pairs, setmetatable, type, CreateFrame
local tostring, tconcat = tostring, table.concat
local UnitIsConnected, UnitIsDeadOrGhost = UnitIsConnected, UnitIsDeadOrGhost
local UnitClass, UnitPowerType, UnitPowerPercent = UnitClass, UnitPowerType, UnitPowerPercent
local UnitGetTotalHealAbsorbs, issecretvalue = UnitGetTotalHealAbsorbs, issecretvalue
local ApplyFont, GetPowerColor = Inner.ApplyFont, Inner.GetPowerColor
local GetSafeHealthPercent, ResolveDisplayName = Inner.GetSafeHealthPercent, Inner.ResolveDisplayName

local TEXTS = mod.RF_TEXTS
local NTEXTS = #TEXTS
local IS_POS = mod.RF_TEXT_POS_INDEX

-- Every text's setting keys under the names the painters read, built once.
local KEYS = {}
for index = 1, NTEXTS do
    local tbl = TEXTS[index]
    KEYS[index] = {
        X = tbl.x,
        Y = tbl.y,
        Size = tbl.size,
        ColorMode = tbl.cm,
        Color = tbl.col,
        CustomFormat = tbl.fmt,
        Above = tbl.above,
    }
end

-- Per kind, as the old element FontStrings: width (a share of the frame width; the
-- name its own), word wrap, alpha and the colour a mode falls back to.
local KIND = {
    name = { width = mod.RF_NAME_WIDTH_FRACTION, wrap = false, a = 1 },
    level = { wrap = false, a = 1 },
    hp = { width = 0.75, wrap = true, a = 0.9 },
    pp = { width = 0.75, wrap = false, a = 0.9 },
    ha = { width = 0.75, wrap = false, a = 0.9, r = 1, g = 0.3, b = 0.3 },
    custom = { width = 0.75, wrap = true, a = 0.9 },
}

local MODES = {
    hp = {
        percent = true,
        percentNoSign = true,
        number = true,
        numberPercent = true,
        percentNumber = true,
        missing = true,
    },
    pp = {
        percent = true,
        percentNoSign = true,
        number = true,
        numberPercent = true,
        percentNumber = true,
    },
    ha = { amount = true, short = true },
}

-------------------------------------------------------------------------------
--  Text plans: built per settings source on first use after a settings write
--  (ns.RF_TextPlanDirty from _RefreshProxyModes). p.all: the shown texts in
--  TEXTS order, p[kind]: those of one kind, p.bySlot[i] by text index,
--  p.reads: the value classes any Custom text reads, p.tick: the health tick
--  has work, p.wantLevel: UNIT_LEVEL is needed, p.nameAttach: the level
--  format in front of the name (the Top Name Bar's too, name shown or not).
-------------------------------------------------------------------------------
local gen, plans = 1, setmetatable({}, { __mode = "k" })

function mod.RF_TextPlanDirty() gen = gen + 1 end

-- A text's position and mode as the plan uses them; nil = not shown. s: the
-- settings (anything indexable), lvlPos: its level position or the client default.
-- Shared with the Text Display tiles, so a tile shows exactly what the frames draw.
local function Shown(tbl, cfg, lvlPos)
    local kind = tbl.kind
    if kind == "level" then
        if IS_POS[lvlPos] then return lvlPos end
        return
    end
    local place = cfg[tbl.pos] or "center"
    if place == "none" then return end
    if kind == "name" then return place end
    if kind == "custom" then
        -- No template, nothing to draw.
        local frame = cfg[tbl.fmt]
        if type(frame) == "string" and frame ~= "" then return place end
        return
    end
    local mode = cfg[tbl.mode]
    if MODES[kind][mode] then return place, mode end
end
mod.RF_TextShown = Shown

local function Build(cfg)
    local p = { gen = gen, all = {}, bySlot = {} }
    local lvlPos = cfg.levelTextPosition or mod.RF_LEVEL_DEFAULT
    p.nameAttach = mod.RF_LEVEL_ATTACH[lvlPos]
    p.wantLevel = (lvlPos ~= "none") or nil
    for index = 1, NTEXTS do
        local tbl = TEXTS[index]
        local place, mode = Shown(tbl, cfg, lvlPos)
        if place then
            local key = KEYS[index]
            local kind = tbl.kind
            local e = {
                i = index,
                k = key,
                pos = place,
                kind = kind,
                mode = mode,
                prop = KIND[kind],
                attach = (kind == "name") and p.nameAttach or nil,
            }
            if kind == "custom" then
                local cc = mod.RF_CustomCompile(cfg[key.CustomFormat])
                e.reads = cc and cc.reads or nil
                if e.reads then
                    local region = p.reads or {}
                    p.reads = region
                    for cls in pairs(e.reads) do
                        region[cls] = true
                    end
                end
            end
            local l = p[kind]
            if not l then
                l = {}
                p[kind] = l
            end
            l[#l + 1] = e
            p.all[#p.all + 1] = e
            p.bySlot[index] = e
        end
    end
    p.tick = (p.hp or p.ha or p.pp or (p.reads and p.reads.hp)) and true or nil
    return p
end

-- What a plan is built from: the level position and every text's position,
-- mode and template. A settings write that leaves them unchanged keeps the
-- plan, so the buttons skip a relayout (the reload paths re-anchor offsets and
-- sizes themselves).
local SIG_KEYS = { "levelTextPosition" }
for index = 1, NTEXTS do
    local tbl = TEXTS[index]
    if tbl.kind ~= "level" then SIG_KEYS[#SIG_KEYS + 1] = tbl.pos end
    if tbl.mode then SIG_KEYS[#SIG_KEYS + 1] = tbl.mode end
    if tbl.fmt then SIG_KEYS[#SIG_KEYS + 1] = tbl.fmt end
end
mod.RF_TEXT_SIG_KEYS = SIG_KEYS
local sigParts = {}
local function Sig(cfg)
    for index = 1, #SIG_KEYS do
        sigParts[index] = tostring(cfg[SIG_KEYS[index]])
    end
    return tconcat(sigParts, "\31")
end

function mod.RF_TextPlan(s)
    local p = plans[s]
    if not p or p.gen ~= gen then
        local sig = Sig(s)
        if p and p.sig == sig then
            p.gen = gen
        else
            p = Build(s)
            p.sig = sig
            plans[s] = p
        end
    end
    return p
end
local Plan = mod.RF_TextPlan

-- True while the raid, party or extra-frames view wants what: "level" (UNIT_LEVEL)
-- or a value class some Custom text reads. Settings-time only: the event syncs.
local VIEWS = { "_scaledProfile", "_scaledPartyProxy", "_scaledExtraProxy" }
function mod.RF_TextWanted(what)
    for index = 1, #VIEWS do
        local s = mod[VIEWS[index]]
        if s then
            local p = Plan(s)
            if (what == "level" and p.wantLevel) or (p.reads and p.reads[what]) then return true end
        end
    end
    return false
end

-- The level format in front of the name, nil without one: the Top Name Bar follows it.
function mod.RF_TextNameAttach(s) return Plan(s).nameAttach end

-------------------------------------------------------------------------------
--  Layout and colour
-------------------------------------------------------------------------------
local function Dead(unitToken) return UnitIsDeadOrGhost(unitToken) or not UnitIsConnected(unitToken) end

-- A text's colour for its colour mode; pr, pg, pb: the unit's power colour when the
-- caller has it. Unknown or unreadable falls back to the content's colour.
local function TextColor(e, unitToken, cfg, pr, pg, pb)
    local mode, P = cfg[e.k.ColorMode], e.prop
    if mode == "accent" then
        local red, green, blue = mod.CludesUI.ResolveActiveAccent()
        if red then return red, green, blue end
    elseif mode == "class" then
        local _, tok = UnitClass(unitToken)
        if tok and not issecretvalue(tok) then
            local cc = mod.CludesUI.GetClassColor(tok)
            if cc then return cc.r, cc.g, cc.b end
        end
    elseif mode == "power" then
        if pr then return pr, pg, pb end
        return GetPowerColor(unitToken)
    else -- "custom"
        local color = cfg[e.k.Color]
        if color then return color.r, color.g, color.b end
    end
    return P.r or 1, P.g or 1, P.b or 1
end

-- Stamped on the FontString (ours) so a repaint with the same colour sets nothing.
local function Tint(fontStr, e, unitToken, s, pr, pg, pb)
    local red, green, blue = TextColor(e, unitToken, s, pr, pg, pb)
    if fontStr._r ~= red or fontStr._g ~= green or fontStr._b ~= blue then
        fontStr._r, fontStr._g, fontStr._b = red, green, blue
        fontStr:SetTextColor(red, green, blue, e.prop.a)
    end
end

-- Show Above Icons per text: the carrier sits where the name's setting puts it (the
-- reload passes level it); a text set the other way goes on a second carrier at the
-- other level (live buttons build it with the first; previews here, on first need).
-- Boss and pet frames have no aura band.
local function CarrierOf(skinData, cfg, e)
    local main = skinData.textCarrier
    if skinData._txFB then return main end
    local base = cfg.nameTextAboveIcons and true or false
    local val = cfg[e.k.Above]
    if val == nil then val = base end
    if (val and true or false) == base then return main end
    local ownerFrame = main:GetParent()
    local alt = skinData._txAlt
    if not alt then
        alt = CreateFrame("Frame", nil, ownerFrame)
        alt:SetAllPoints(main)
        skinData._txAlt = alt
    end
    local lvl = ownerFrame:GetFrameLevel() + (val and (mod.LVL_AURA + 6) or mod.LVL_TEXT)
    if alt:GetFrameLevel() ~= lvl then alt:SetFrameLevel(lvl) end
    return alt
end

-- Font, wrap and anchor of one shown text. The name sits on the decoration host (the
-- Party Frames kit: its stock name spot) and hides under the Top Name Bar; the others
-- sit on the bar host. Power Text shows only while the power bar does (d._pwtOn).
-- Boss and pet frames (d._txFB) bring their own host (d._txHost) and width (d._txW),
-- never wrap and have no Top Name Bar. Preview frames keep their bar as d._health.
local function Place(skinData, cfg, e, fontStr)
    local key, P, g, fb = e.k, e.prop, skinData.kitG, skinData._txFB
    local health = skinData.health or skinData._health
    local posX, posY = cfg[key.X] or 0, cfg[key.Y] or 0
    local fw = skinData._txW or cfg.frameWidth or 72
    local carrier = CarrierOf(skinData, cfg, e)
    if fontStr._cr ~= carrier then
        fontStr:SetParent(carrier)
        fontStr._cr = carrier
    end
    ApplyFont(fontStr, cfg[key.Size] or 10)
    fontStr:SetWordWrap(P.wrap and not fb)
    fontStr._r = nil
    if e.kind == "name" and g then
        fontStr:SetWidth(g.name.w)
        fontStr:SetHeight(0)
        mod.RF_KitSpot(g.name, fontStr, skinData.kitOwner, posX, posY)
        fontStr:SetJustifyH("LEFT")
        fontStr:SetJustifyV(g.name.jv)
        local txt = fontStr:GetText()
        fontStr:SetText("")
        fontStr:SetText(txt or "")
    elseif e.kind == "name" then
        if cfg.topNameBarEnabled and not fb then
            fontStr:Hide()
            return
        end
        mod.AnchorRFText(
            fontStr,
            skinData._txHost or mod.RF_AnchorHost(health, cfg),
            e.pos,
            posX,
            posY,
            fw * P.width
        )
    else
        local wid = P.width and (g and g.health.w or fw * P.width)
        if not wid then fontStr:SetWidth(0) end
        mod.AnchorRFText(fontStr, skinData._txHost or mod.RF_BarHost(health, cfg), e.pos, posX, posY, wid)
    end
    fontStr:SetShown(e.kind ~= "pp" or skinData._pwtOn == true)
end

-- Boss and pet frames show no level and have no power bar.
local FB_SKIP = { level = true, pp = true }

-- Builds (on first need), fonts, anchors and shows the texts of s's plan on a
-- live button and hides the others. Re-run by every reload and kit pass; the paints
-- run it themselves when the plan changed since (ns._RFTextReady).
function mod.RF_TextLayout(skinData, s)
    local p = Plan(s)
    local pool = skinData._tx
    if not pool then
        pool = {}
        skinData._tx = pool
    end
    local fb = skinData._txFB
    for index = 1, NTEXTS do
        local e, fontStr = p.bySlot[index], pool[index]
        if e and fb and FB_SKIP[e.kind] then e = nil end
        if e then
            if not fontStr then
                fontStr = skinData.textCarrier:CreateFontString(nil, "OVERLAY")
                fontStr._cr = skinData.textCarrier
                pool[index] = fontStr
            end
            Place(skinData, s, e, fontStr)
        elseif fontStr then
            fontStr:Hide()
        end
    end
    skinData._txL, skinData._txP, skinData._txS = p, p, s
end

-- The name's width on the resize paths that know the bar width better than
-- s.frameWidth (extra frames, party drags); the kit keeps its stock width.
function mod.RF_TextNameWidth(skinData, wid)
    local l = skinData._txL and skinData._txL.name
    if not l or skinData.kitG then return end
    for jdx = 1, #l do
        skinData._tx[l[jdx].i]:SetWidth(wid * l[jdx].prop.width)
    end
end

-- Fonts only, for the live resize drags that rescale sizes without a layout pass.
function mod.RF_TextFonts(skinData, cfg)
    local p = skinData._txL
    if not p then return end
    local all, pool = p.all, skinData._tx
    for jdx = 1, #all do
        ApplyFont(pool[all[jdx].i], cfg[all[jdx].k.Size] or 10)
    end
end

-- Stamps the button's plan and settings for the event paths; lays out first when
-- the plan changed. Returns the plan.
local function Ready(skinData, s)
    local p = Plan(s)
    if skinData._txL ~= p then mod.RF_TextLayout(skinData, s) end
    skinData._txP, skinData._txS = p, s
    return p
end
mod._RFTextReady = Ready

-------------------------------------------------------------------------------
--  Painters. Values only reach a format setter (secret-safe). Health, Power and
--  Heal Absorb Text blank while dead or offline (the status text names it); the
--  name, the level and Custom stay (Custom's tags name the status).
-------------------------------------------------------------------------------
local function PaintName(fontStr, e, unitToken, s, fb)
    if e.attach and not fb then
        mod._RFNameWithLevel(fontStr, ResolveDisplayName(unitToken, true, s), unitToken, e.attach)
    else
        fontStr:SetText(ResolveDisplayName(unitToken, true, s))
    end
end

local function PaintHealAbsorb(fontStr, e, unitToken, s, gone)
    if gone then
        fontStr:SetText("")
        return
    end
    mod.FormatHealAbsorbInto(
        fontStr,
        (UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(unitToken)) or 0,
        e.mode
    )
    Tint(fontStr, e, unitToken, s)
end

-- d._txArgs[i]: the values text i was last painted with on this button. A repaint for
-- value classes a / b reads only the tags reading them (a health tick never resolves
-- the name again); a full paint (a nil) reads every tag.
local function PaintCustom(fontStr, e, unitToken, cfg, skinData, a, b)
    local all = skinData._txArgs
    if not all then
        all = {}
        skinData._txArgs = all
    end
    local args = all[e.i]
    if not args then
        args = {}
        all[e.i] = args
    end
    mod.RF_CustomTextInto(fontStr, cfg[e.k.CustomFormat], unitToken, cfg, nil, args, a, b)
end

-- The full paint's share: every text but Power Text (the power paint owns it).
function mod.RF_TextFull(skinData, s, unitToken)
    local p = Ready(skinData, s)
    local all, pool, fb = p.all, skinData._tx, skinData._txFB
    local gone = Dead(unitToken)
    local pct = p.hp and not gone and GetSafeHealthPercent(unitToken)
    for jdx = 1, #all do
        local e = all[jdx]
        local kind, fontStr = e.kind, pool[e.i]
        if kind == "name" then
            PaintName(fontStr, e, unitToken, s, fb)
            Tint(fontStr, e, unitToken, s)
        elseif kind == "level" then
            if not fb then
                mod._RFLevelInto(fontStr, unitToken)
                Tint(fontStr, e, unitToken, s)
            end
        elseif kind == "custom" then
            PaintCustom(fontStr, e, unitToken, s, skinData)
            Tint(fontStr, e, unitToken, s)
        elseif kind == "hp" then
            if gone then
                fontStr:SetText("")
            else
                mod.RF_HealthTextInto(fontStr, e.mode, pct, unitToken)
                Tint(fontStr, e, unitToken, s)
            end
        elseif kind == "ha" then
            PaintHealAbsorb(fontStr, e, unitToken, s, gone)
        end
    end
end

-- Name and Level texts and the Custom texts' names and levels (nickname changes,
-- UNIT_LEVEL).
function mod.RF_TextNames(skinData, unitToken)
    local p = skinData._txP
    if not p then return end
    local s, pool, fb = skinData._txS, skinData._tx, skinData._txFB
    local l = p.name
    if l then
        for jdx = 1, #l do
            local e = l[jdx]
            PaintName(pool[e.i], e, unitToken, s, fb)
            Tint(pool[e.i], e, unitToken, s)
        end
    end
    l = not fb and p.level
    if l then
        for jdx = 1, #l do
            mod._RFLevelInto(pool[l[jdx].i], unitToken)
        end
    end
    if p.reads and p.reads.id then mod.RF_TextRepaintCustom(skinData, unitToken, "id") end
end

-- Heal Absorb Texts (the absorb-only event path).
function mod.RF_TextHealAbsorb(skinData, unitToken)
    local p = skinData._txP
    local l = p and p.ha
    if not l then return end
    local s, pool, gone = skinData._txS, skinData._tx, Dead(unitToken)
    for jdx = 1, #l do
        PaintHealAbsorb(pool[l[jdx].i], l[jdx], unitToken, s, gone)
    end
end

-- The Custom texts reading value class a or b (the event paths that move only those).
function mod.RF_TextRepaintCustom(skinData, unitToken, a, b)
    local p = skinData._txP
    local region = p and p.reads
    if not (region and (region[a] or (b and region[b]))) then return end
    local s, pool, l = skinData._txS, skinData._tx, p.custom
    for jdx = 1, #l do
        local e = l[jdx]
        local er = e.reads
        if er and (er[a] or (b and er[b])) then PaintCustom(pool[e.i], e, unitToken, s, skinData, a, b) end
    end
end
local RepaintCustom = mod.RF_TextRepaintCustom

-------------------------------------------------------------------------------
--  Power Text: shown only while the button's power bar shows (d._pwtOn). The
--  full power paint shows it ahead of the identity edge that colours it; the
--  value rides every power value push; dead/offline blanks it on the edge the
--  health tick sees (d._pwtGone, cleared by the full power paint).
-------------------------------------------------------------------------------
function mod.RF_TextPowerShow(skinData, s)
    local l = Ready(skinData, s).pp
    if not l then
        skinData._pwtOn = nil
        return
    end
    skinData._pwtOn, skinData._pwtGone = true, nil
    local pool = skinData._tx
    for jdx = 1, #l do
        pool[l[jdx].i]:Show()
    end
end

function mod.RF_TextPowerHide(skinData)
    if not skinData._pwtOn then return end
    skinData._pwtOn = nil
    local l = skinData._txP and skinData._txP.pp
    if not l then return end
    local pool = skinData._tx
    for jdx = 1, #l do
        pool[l[jdx].i]:Hide()
    end
end

-- A power value push. full: the full power paint, whose tail paints the Custom texts.
function mod.RF_TextPower(skinData, unitToken, ppct, pType, full)
    local p = skinData._txP
    if not p then return end
    local l = skinData._pwtOn and p.pp
    if l then
        local pool = skinData._tx
        for jdx = 1, #l do
            mod.RF_PowerTextInto(pool[l[jdx].i], l[jdx].mode, ppct, unitToken, pType)
        end
    end
    if not full and p.reads and p.reads.pp then RepaintCustom(skinData, unitToken, "pp") end
end

-- Power Text colour on the identity edge; pr, pg, pb: the unit's power colour.
function mod.RF_TextPowerColor(skinData, unitToken, s, pr, pg, pb)
    local l = skinData._pwtOn and skinData._txP and skinData._txP.pp
    if not l then return end
    local pool = skinData._tx
    for jdx = 1, #l do
        Tint(pool[l[jdx].i], l[jdx], unitToken, s, pr, pg, pb)
    end
end

local function PowerLife(skinData, l, unitToken, gone)
    if skinData._pwtGone == gone then return end
    skinData._pwtGone = gone
    local pool = skinData._tx
    if gone then
        for jdx = 1, #l do
            pool[l[jdx].i]:SetText("")
        end
        return
    end
    local pType = skinData._pwType or UnitPowerType(unitToken) or 0
    local ppct = UnitPowerPercent(unitToken, pType, true, CurveConstants.ScaleTo100)
    for jdx = 1, #l do
        mod.RF_PowerTextInto(pool[l[jdx].i], l[jdx].mode, ppct, unitToken, pType)
    end
end

-- The health tick's share (callers gate on d._txP.tick): Health and Heal Absorb
-- Text, Power Text's dead/offline edge, and the Custom texts reading health.
-- allCustom: every Custom text (boss and pet frames, which have no other text events).
function mod.RF_TextHealth(skinData, unitToken, pct, gone, allCustom)
    local p = skinData._txP
    local s, pool = skinData._txS, skinData._tx
    local l = p.hp
    if l then
        for jdx = 1, #l do
            local e = l[jdx]
            local fontStr = pool[e.i]
            if gone then
                fontStr:SetText("")
            else
                mod.RF_HealthTextInto(fontStr, e.mode, pct, unitToken)
                Tint(fontStr, e, unitToken, s)
            end
        end
    end
    l = p.ha
    if l then
        for jdx = 1, #l do
            PaintHealAbsorb(pool[l[jdx].i], l[jdx], unitToken, s, gone)
        end
    end
    l = skinData._pwtOn and p.pp
    if l then PowerLife(skinData, l, unitToken, gone) end
    l = allCustom and p.custom
    if l then
        for jdx = 1, #l do
            PaintCustom(pool[l[jdx].i], l[jdx], unitToken, s, skinData)
        end
    elseif p.reads and p.reads.hp then
        RepaintCustom(skinData, unitToken, "hp")
    end
end

-------------------------------------------------------------------------------
--  Previews: no unit, made-up values in pv (hpPct, hpPer, ppPct, ppPer, ha:
--  the heal absorb amount, name: as the name text shows it, dead, offline,
--  power: the power bar shows, class and pToken: the sample member's class
--  and power type for the colours). The same layout and rules as live.
-------------------------------------------------------------------------------
local function PvPaint(fontStr, e, cfg, pv, fb)
    local kind = e.kind
    if kind == "name" then
        if e.attach and not fb then
            fontStr:SetFormattedText(e.attach[1], mod._RFPreviewLevel(), pv.name or "")
        else
            fontStr:SetText(pv.name or "")
        end
    elseif kind == "level" then
        fontStr:SetFormattedText("%d", mod._RFPreviewLevel())
    elseif kind == "custom" then
        mod.RF_CustomTextInto(fontStr, cfg[e.k.CustomFormat], nil, cfg, pv)
    elseif pv.dead or pv.offline then
        fontStr:SetText("")
        return
    elseif kind == "hp" then
        mod.RF_HealthTextInto(fontStr, e.mode, pv.hpPct or 100, nil, pv.hpPer or 1)
    elseif kind == "pp" then
        mod.RF_PowerTextInto(fontStr, e.mode, pv.ppPct or 100, nil, nil, pv.ppPer or 1)
    else -- "ha"
        mod.FormatHealAbsorbInto(fontStr, pv.ha or 0, e.mode)
    end
    local P = e.prop
    local red, green, blue = mod.RF_PreviewTextColor(
        cfg[e.k.ColorMode],
        cfg[e.k.Color],
        pv.class,
        P.r or 1,
        P.g or 1,
        P.b or 1,
        pv.pToken
    )
    fontStr:SetTextColor(red, green, blue, P.a)
end

-- Lays out and paints every shown text of a preview frame (d: the frame or a state with
-- textCarrier, _health and, for a replica, _txW). Keeps pv for the animated previews.
function mod.RF_TextPreview(skinData, s, pv)
    skinData._pwtOn = pv.power or nil
    mod.RF_TextLayout(skinData, s)
    local all, pool, fb = skinData._txL.all, skinData._tx, skinData._txFB
    for jdx = 1, #all do
        local e = all[jdx]
        if not (fb and FB_SKIP[e.kind]) then PvPaint(pool[e.i], e, s, pv, fb) end
    end
    skinData._txPv = pv
end

-- An animated preview's step after it moved pv: the texts following health ("hp") or
-- power ("pp"), Custom texts reading it included.
function mod.RF_TextPreviewTick(skinData, what)
    local p, pv = skinData._txL, skinData._txPv
    if not (p and pv) then return end
    local all, pool, s, fb = p.all, skinData._tx, skinData._txS, skinData._txFB
    for jdx = 1, #all do
        local e = all[jdx]
        local kind = e.kind
        if
            (kind == what or (kind == "custom" and e.reads and e.reads[what]))
            and not (fb and FB_SKIP[kind])
        then
            PvPaint(pool[e.i], e, s, pv, fb)
        end
    end
end

-- The text inputs the boss/pet styler reads, written from t[n + 1] for the pet frames'
-- restyle fingerprint: the plan's signature (positions, modes, templates), then each
-- text's offsets and size. ns.RF_TEXT_STYLE_N values; returns the last index written.
mod.RF_TEXT_STYLE_N = 1 + 3 * NTEXTS
function mod.RF_TextStyleInputs(tbl, num, cfg)
    num = num + 1
    tbl[num] = Plan(cfg).sig
    for index = 1, NTEXTS do
        local key = KEYS[index]
        tbl[num + 1], tbl[num + 2], tbl[num + 3] = cfg[key.X], cfg[key.Y], cfg[key.Size]
        num = num + 3
    end
    return num
end

Inner.broken = false
