if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  XP bar effects (the XP Bar tab's Effects section)
--
--  Layered on the XP bar (CUI_ActionBars_XPBar.lua) without changing how it
--  paints: a soft shine on the fill with a spark at its end, fine stripes and
--  a bright edge on the rested band, a pulse and a rising "+XP" when a quest
--  is handed in, a glow and star when completed quests would level you, a
--  flash that drains away on a level-up, an XP breakdown in the hover tooltip
--  and the bar hidden in battlegrounds and arenas. Each is a toggle on the bar's
--  settings (nil = on; showInPvP nil = hidden there). Horizontal bars only for
--  the placed effects; the tooltip and the PvP hide work on any bar.
-------------------------------------------------------------------------------
local _, mod = ...
local CUI = _G.CludesUI
local ABAR = mod.EAB

local WHITE = "Interface\\Buttons\\WHITE8X8"
local MEDIA = "Interface\\AddOns\\CludesUI\\media\\"
local STRIPES = MEDIA .. "xp-stripes.tga"
local STAR = MEDIA .. "xp-star.tga"

local LOOK = { SHEEN = 0.16, SHADE = 0.22, SPARK_W = 8, SPARK = 0.6, EDGE = 0.95, STRIPE = 0.35, LIFT = 1.6 }
local PULSE = { FLASH = 0.9, FADE = 0.8, RISE = 18, HOLD = 0.35, TEXT_FADE = 0.9, SIZE = 13, GAP = 2, EDGE = 24 }
local READY = { LOW = 0.1, HIGH = 0.5, BEAT = 0.9, STAR = 16 }
local LEVEL = { FLASH = 0.75, IN = 0.15, DRAIN = 0.7, GONE = 0.01 }
local KILL = { BASE = 45, PER_LEVEL = 5, RESTED = 2 }
local PVP = { pvp = true, arena = true }
local SETTLE = 0.2

local FX = {}
mod.XPBarFX = FX

local function Cfg()
    local p = ABAR and ABAR.db and ABAR.db.profile
    return p and p.bars and p.bars.XPBar
end

-- An effect is on unless its toggle was turned off.
function FX.On(cfg, key) return cfg ~= nil and cfg[key] ~= false end

local function Lift(c) return math.min(c * LOOK.LIFT, 1) end

local function Grouped(n)
    n = math.floor(n)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    return tostring(n)
end

local function HideParent(group) group:GetParent():Hide() end

local function Fade(region, from, duration, delay)
    local group = region:CreateAnimationGroup()
    local alpha = group:CreateAnimation("Alpha")
    alpha:SetFromAlpha(from)
    alpha:SetToAlpha(0)
    alpha:SetDuration(duration)
    alpha:SetStartDelay(delay or 0)
    group:SetScript("OnFinished", HideParent)
    return group
end

local function Beat(region)
    local group = region:CreateAnimationGroup()
    group:SetLooping("BOUNCE")
    local alpha = group:CreateAnimation("Alpha")
    alpha:SetFromAlpha(READY.LOW)
    alpha:SetToAlpha(READY.HIGH)
    alpha:SetDuration(READY.BEAT)
    return group
end

local function Rise(region)
    local group = Fade(region, 1, PULSE.TEXT_FADE, PULSE.HOLD)
    local move = group:CreateAnimation("Translation")
    move:SetOffset(0, PULSE.RISE)
    move:SetDuration(PULSE.HOLD + PULSE.TEXT_FADE)
    return group
end

local function Drain(region)
    local group = region:CreateAnimationGroup()
    local light = group:CreateAnimation("Alpha")
    light:SetFromAlpha(0)
    light:SetToAlpha(LEVEL.FLASH)
    light:SetDuration(LEVEL.IN)
    light:SetOrder(1)
    local shrink = group:CreateAnimation("Scale")
    if shrink.SetScaleFrom then
        shrink:SetScaleFrom(1, 1)
        shrink:SetScaleTo(LEVEL.GONE, 1)
    else
        shrink:SetFromScale(1, 1)
        shrink:SetToScale(LEVEL.GONE, 1)
    end
    shrink:SetOrigin("RIGHT", 0, 0)
    shrink:SetDuration(LEVEL.DRAIN)
    shrink:SetOrder(2)
    local fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(LEVEL.FLASH)
    fade:SetToAlpha(0)
    fade:SetDuration(LEVEL.DRAIN)
    fade:SetOrder(2)
    group:SetScript("OnFinished", HideParent)
    return group
end

local function Flat(parent, sub, blend)
    local tex = parent:CreateTexture(nil, "OVERLAY", nil, sub)
    tex:SetTexture(WHITE)
    if blend then tex:SetBlendMode(blend) end
    tex:Hide()
    return tex
end

local function Gradient(tex, dir, r1, g1, b1, a1, r2, g2, b2, a2)
    if CreateColor and tex.SetGradient then
        tex:SetGradient(dir, CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
    else
        tex:SetVertexColor(r2, g2, b2, math.max(a1, a2))
    end
end

-- The effect layers, built once per XP bar frame (the live bar and the
-- options preview): a frame over the fill for the shine, spark and pulses, and
-- one over the whole bar for the star and the "+XP" text.
function FX.Build(widget)
    local bar = widget and widget._bar
    if not bar or widget._fx then return end
    local fx = CreateFrame("Frame", nil, bar)
    fx:SetAllPoints(bar)
    fx:SetFrameLevel(bar:GetFrameLevel() + 2)
    widget._fx = fx

    fx.sheen = Flat(fx, 0)
    Gradient(fx.sheen, "VERTICAL", 1, 1, 1, 0, 1, 1, 1, LOOK.SHEEN)
    fx.shade = Flat(fx, 0)
    Gradient(fx.shade, "VERTICAL", 0, 0, 0, LOOK.SHADE, 0, 0, 0, 0)
    fx.spark = Flat(fx, 2, "ADD")
    fx.spark:SetWidth(LOOK.SPARK_W)
    Gradient(fx.spark, "HORIZONTAL", 1, 1, 1, 0, 1, 1, 1, LOOK.SPARK)

    fx.stripes = fx:CreateTexture(nil, "ARTWORK", nil, 7)
    fx.stripes:SetTexture(STRIPES, "REPEAT", "REPEAT")
    fx.stripes:SetHorizTile(true)
    fx.stripes:SetVertTile(true)
    fx.stripes:Hide()
    fx.edge = Flat(fx, 1)
    fx.edge:SetWidth(1)

    fx.ready = Flat(fx, 3, "ADD")
    fx.readyBeat = Beat(fx.ready)
    fx.gain = Flat(fx, 4, "ADD")
    fx.gainFade = Fade(fx.gain, PULSE.FLASH, PULSE.FADE)
    fx.level = Flat(fx, 5, "ADD")
    fx.level:SetPoint("TOPLEFT")
    fx.level:SetPoint("BOTTOMLEFT")
    fx.levelDrain = Drain(fx.level)

    local top = CreateFrame("Frame", nil, widget)
    top:SetAllPoints(widget)
    top:SetFrameLevel(widget:GetFrameLevel() + 8)
    fx.top = top
    fx.star = top:CreateTexture(nil, "OVERLAY")
    fx.star:SetTexture(STAR)
    fx.star:SetSize(READY.STAR, READY.STAR)
    fx.star:SetPoint("CENTER", widget, "TOPRIGHT")
    fx.star:Hide()
    fx.starBeat = Beat(fx.star)
    fx.text = top:CreateFontString(nil, "OVERLAY")
    fx.text:SetFont(CUI.GetFontPath("actionBars"), PULSE.SIZE, "OUTLINE")
    fx.text:Hide()
    fx.textRise = Rise(fx.text)
end

-- A span of the bar from a to b (values 0..mx) on the fx frame.
local function Span(tex, fx, w, mx, a, b)
    local x1, x2 = w * a / mx, w * b / mx
    if x2 - x1 < 1 then
        tex:Hide()
        return
    end
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", fx, "TOPLEFT", x1, 0)
    tex:SetPoint("BOTTOMLEFT", fx, "BOTTOMLEFT", x1, 0)
    tex:SetWidth(x2 - x1)
    tex:Show()
end

local function SetReady(fx, on, r, g, b)
    if on then
        fx.ready:SetVertexColor(Lift(r), Lift(g), Lift(b), 1)
        fx.star:SetVertexColor(Lift(r), Lift(g), Lift(b), 1)
        fx.ready:Show()
        fx.star:Show()
        if not fx.readyBeat:IsPlaying() then
            fx.readyBeat:Play()
            fx.starBeat:Play()
        end
    elseif fx.star:IsShown() then
        fx.readyBeat:Stop()
        fx.starBeat:Stop()
        fx.ready:Hide()
        fx.star:Hide()
    end
end

-- Completed quest XP (every completed quest in the log, whatever the Quest
-- XP Overlay's filters), and in-progress XP for the tooltip.
local questDone, questOpen = 0, 0
function FX.ScanQuests()
    questDone, questOpen = 0, 0
    local QL = C_QuestLog
    if not (GetQuestLogRewardXP and QL and QL.GetNumQuestLogEntries) then return end
    for index = 1, QL.GetNumQuestLogEntries() do
        local q = QL.GetQuestIDForLogIndex(index)
        if q and q > 0 then
            local xp = GetQuestLogRewardXP(q) or 0
            if QL.IsComplete(q) then
                questDone = questDone + xp
            else
                questOpen = questOpen + xp
            end
        end
    end
end
function FX.QuestXP() return questDone, questOpen end

-- After each fill paint: place the shine, spark, rested stripes and edge, the
-- ready glow, and a pending quest pulse.
function FX.Paint(widget, cfg, current, mx, rested)
    local fx = widget and widget._fx
    if not (fx and cfg) then return end
    local w = widget._bar:GetWidth() or 0
    local horizontal = (cfg.orientation or "HORIZONTAL") == "HORIZONTAL"
    if not horizontal or w < 2 or mx <= 0 then
        for _, k in ipairs({ "sheen", "shade", "spark", "stripes", "edge", "gain" }) do
            fx[k]:Hide()
        end
        SetReady(fx, false)
        return
    end
    widget._fxCur, widget._fxMax, widget._fxRest = current, mx, rested
    local h = widget._bar:GetHeight() or 0
    local x = w * math.min(current, mx) / mx

    local shine = FX.On(cfg, "fxShine") and x >= 1
    if shine then
        fx.sheen:ClearAllPoints()
        fx.sheen:SetPoint("TOPLEFT", fx, "TOPLEFT", 0, 0)
        fx.sheen:SetSize(x, math.max(h / 2, 1))
        fx.sheen:Show()
        fx.shade:ClearAllPoints()
        fx.shade:SetPoint("BOTTOMLEFT", fx, "BOTTOMLEFT", 0, 0)
        fx.shade:SetSize(x, math.max(h / 3, 1))
        fx.shade:Show()
    else
        fx.sheen:Hide()
        fx.shade:Hide()
    end
    fx.spark:ClearAllPoints()
    fx.spark:SetPoint("TOPRIGHT", fx, "TOPLEFT", x, 0)
    fx.spark:SetPoint("BOTTOMRIGHT", fx, "BOTTOMLEFT", x, 0)
    fx.spark:SetShown(shine and x >= LOOK.SPARK_W and x < w)

    -- Rested: stripes over the band past the fill and a bright 1 px edge.
    local restColor = cfg.restedColor
    local rr, rg, rb = restColor and restColor.r or 0.29, restColor and restColor.g or 0.47, restColor and restColor.b or 0.87
    local restEnd = math.min(current + (rested or 0), mx)
    if rested and rested > 0 and FX.On(cfg, "fxStripes") then
        fx.stripes:SetVertexColor(Lift(rr), Lift(rg), Lift(rb), LOOK.STRIPE)
        Span(fx.stripes, fx, w, mx, math.min(current, mx), restEnd)
        if restEnd < mx then
            fx.edge:SetVertexColor(Lift(rr), Lift(rg), Lift(rb), LOOK.EDGE)
            fx.edge:ClearAllPoints()
            fx.edge:SetPoint("TOPLEFT", fx, "TOPLEFT", w * restEnd / mx - 1, 0)
            fx.edge:SetPoint("BOTTOMLEFT", fx, "BOTTOMLEFT", w * restEnd / mx - 1, 0)
            fx.edge:Show()
        else
            fx.edge:Hide()
        end
    else
        fx.stripes:Hide()
        fx.edge:Hide()
    end

    -- Ready to level: completed quests cover the rest of the level.
    local qr, qg, qb = mod.XPQuestColor(cfg, true)
    local ready = not widget._fxPreview and FX.On(cfg, "fxReady") and questDone > 0 and current + questDone >= mx
    if ready then Span(fx.ready, fx, w, mx, math.min(current, mx), mx) end
    SetReady(fx, ready, qr, qg, qb)

    -- A handed-in quest: once the fill moved (or the settle time ran out).
    local gained = widget._fxGain
    if gained and (x ~= widget._fxX or GetTime() - (widget._fxGainAt or 0) >= SETTLE) then
        widget._fxGain = nil
        local from = math.max(0, current - gained)
        fx.gain:SetVertexColor(Lift(qr), Lift(qg), Lift(qb), 1)
        Span(fx.gain, fx, w, mx, from, math.min(current, mx))
        if fx.gain:IsShown() then
            fx.gainFade:Stop()
            fx.gainFade:Play()
        end
        fx.text:SetTextColor(Lift(qr), Lift(qg), Lift(qb), 1)
        fx.text:SetText("+" .. Grouped(gained))
        fx.text:ClearAllPoints()
        fx.text:SetPoint("BOTTOM", widget, "TOPLEFT", math.min(math.max(x, PULSE.EDGE), w - PULSE.EDGE), PULSE.GAP)
        fx.text:Show()
        fx.textRise:Stop()
        fx.textRise:Play()
    end
    widget._fxX = x
end

function FX.Gain(widget, amount)
    if not (widget and widget._fx) or not FX.On(Cfg(), "fxPulse") then return end
    widget._fxGain = (widget._fxGain or 0) + amount
    widget._fxGainAt = GetTime()
end

function FX.LevelUp(widget)
    local fx = widget and widget._fx
    local cfg = Cfg()
    if not fx or not FX.On(cfg, "fxLevelFlash") or (cfg.orientation or "HORIZONTAL") ~= "HORIZONTAL" then return end
    local r, g, b = CUI.GetAccentColor()
    fx.level:SetVertexColor(r, g, b, 1)
    fx.level:SetWidth(math.max(widget._bar:GetWidth() or 1, 1))
    fx.level:Show()
    fx.levelDrain:Stop()
    fx.levelDrain:Play()
end

-- About how many kills of your level are left (rested doubles a kill's XP
-- until the rested pool runs out).
function FX.Kills(level, left, rested)
    local kill = KILL.BASE + KILL.PER_LEVEL * level
    local boosted = math.min(math.ceil(left / (KILL.RESTED * kill)), math.floor((rested or 0) / kill))
    local rest = left - boosted * KILL.RESTED * kill
    return boosted + math.max(0, math.ceil(rest / kill))
end

-- The breakdown lines under the bar's own tooltip.
function FX.Breakdown(tip)
    local xp, mx = UnitXP("player"), math.max(UnitXPMax("player"), 1)
    local left = math.max(mx - xp, 0)
    local rested = GetXPExhaustion() or 0
    local Pal = CUI.Kit and CUI.Kit.Palette
    local mr, mg, mb = 0.7, 0.7, 0.7
    if Pal and Pal.muted then mr, mg, mb = Pal.muted[1] or mr, Pal.muted[2] or mg, Pal.muted[3] or mb end
    tip:AddLine(" ")
    if questDone > 0 then
        local label = questDone >= left and CUI.L("Completed Quests (enough to level)") or CUI.L("Completed Quests")
        tip:AddDoubleLine(label, Grouped(questDone), mr, mg, mb, 1, 1, 1)
    end
    if questOpen > 0 then tip:AddDoubleLine(CUI.L("Quests in Progress"), Grouped(questOpen), mr, mg, mb, 1, 1, 1) end
    tip:AddDoubleLine(
        CUI.L("Kills to Level"),
        format("~%d", FX.Kills(UnitLevel("player") or 1, left, rested)),
        mr,
        mg,
        mb,
        1,
        1,
        1
    )
end

-- Battlegrounds and arenas count as max level for the bar, so every path that
-- hides it there (layout, sync, tooltip) agrees.
local inPvP = false
local function InPvP()
    local _, kind = IsInInstance()
    return PVP[kind] == true
end
local AtMax = mod.XPBarAtMaxLevel
function mod.XPBarAtMaxLevel()
    if inPvP then
        local cfg = Cfg()
        if cfg and not cfg.showInPvP then return true end
    end
    return AtMax()
end

-- Every XP bar frame gets the layers; each fill paint places them.
local CreateFrameFn = mod.CreateXPBarFrame
function mod.CreateXPBarFrame(updateFunc, hostFrame)
    local holderFrame = CreateFrameFn(updateFunc, hostFrame)
    if hostFrame then holderFrame._fxPreview = true end
    FX.Build(holderFrame)
    if holderFrame._bar then
        holderFrame._bar:HookScript("OnSizeChanged", function()
            if holderFrame._fxMax then
                FX.Paint(holderFrame, Cfg(), holderFrame._fxCur, holderFrame._fxMax, holderFrame._fxRest)
            end
        end)
    end
    if not hostFrame then
        holderFrame:HookScript("OnEnter", function(self)
            if GameTooltip:IsOwned(self) and FX.On(Cfg(), "fxBreakdown") then
                FX.Breakdown(GameTooltip)
                GameTooltip:Show()
            end
        end)
    end
    return holderFrame
end

local PaintFill = mod.PaintXPFill
function mod.PaintXPFill(widget, cfg, current, mx, rested)
    PaintFill(widget, cfg, current, mx, rested)
    FX.Paint(widget, cfg, current, mx, rested)
end

local scanQueued
local function Live() return mod.dataBarFrames and mod.dataBarFrames.XPBar end
local function Repaint()
    local live = Live()
    if live and live._fxMax and live:IsShown() then
        FX.Paint(live, Cfg(), UnitXP("player"), math.max(UnitXPMax("player"), 1), GetXPExhaustion() or 0)
    end
end
local function QueueScan()
    if scanQueued then return end
    scanQueued = true
    C_Timer.After(SETTLE, function()
        scanQueued = nil
        FX.ScanQuests()
        Repaint()
    end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("QUEST_TURNED_IN")
ev:RegisterEvent("QUEST_LOG_UPDATE")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, event, _, questXP)
    if event == "QUEST_TURNED_IN" then
        if questXP and questXP > 0 then
            FX.Gain(Live(), questXP)
            C_Timer.After(SETTLE, Repaint)
        end
    elseif event == "QUEST_LOG_UPDATE" then
        QueueScan()
    elseif event == "PLAYER_LEVEL_UP" then
        FX.LevelUp(Live())
        QueueScan()
    elseif event == "PLAYER_ENTERING_WORLD" then
        local now = InPvP()
        if now ~= inPvP then
            inPvP = now
            if Live() and mod.ApplyDataBarLayout then mod.ApplyDataBarLayout("XPBar") end
        end
        QueueScan()
    end
end)
