if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_Glimmer.lua  (WoW Forever only)
--  Glimmer:
--    Object Highlights  herbs, ore, chests, quest objects, quest givers, your
--                       fishing bobber and lootable corpses light up as you
--                       walk up to them (glow, sparkles, ring, beam or
--                       brackets), in their skill-up colour for herbs and
--                       ore, with a line under it ("Skill-up likely",
--                       "Requires Mining 65", the quest objective).
--    Minimap Spots      every spot herbs and ore grow near you, on the
--                       minimap, ringed in its skill-up colour.
--    Gathered on Map    each herb and vein you gather, on the world map.
--  (Loot sparkles are Loot Sparkles; node skill in tooltips is Gathering
--  Skill in Tooltips.)
--
--  How the highlight works: it is the game's soft interact target (the
--  object in front of you that Interact With Target would use). Glimmer
--  holds the soft interact settings on (SoftTargetInteract, its range and
--  arc, the icon on game objects, a nameplate for the target), saved and put
--  back when it is turned off (CludesUI.HoldCVar). The target is sorted by
--  its object ID (GlimmerData's nodes) or by the cursor the game would show
--  on it; the effect is drawn on its nameplate, under it, and follows it.
--  Paused in combat (the game locks those settings) and, by default, in
--  dungeons. Nothing here is a secure action.
-------------------------------------------------------------------------------
local _, module = ...

local NODE_INFO = module.GLIMMER_NODES or {}
local KIND_LIST = { "ore", "herb", "quest", "giver", "chest", "bobber", "corpse" }

local DEFAULT_SET = {
    enabled = false,
    style = "sparkles",
    size = 1,
    brightness = 1,
    skillColors = true,
    showLine = true,
    hideInstance = true,
    hideLocked = false,
    range = 15,
    arc = 2,
    onlyHighlighted = true,
    ore = true,
    herb = true,
    quest = true,
    giver = true,
    chest = true,
    bobber = true,
    corpse = false,
    minimapIcons = false,
    minimapSize = 14,
    myProfessions = true,
    gatheredPins = false,
    gatheredPinSize = 18,
    oreR = 0.88, oreG = 0.64, oreB = 0.35,
    herbR = 0.49, herbG = 0.83, herbB = 0.54,
    questR = 1, questG = 0.84, questB = 0.35,
    giverR = 1, giverG = 0.84, giverB = 0.35,
    chestR = 0.30, chestG = 0.71, chestB = 0.96,
    bobberR = 1, bobberG = 0.48, bobberB = 0.42,
    corpseR = 0.74, corpseG = 0.56, corpseB = 1,
}
local F = module.Feature("glimmer", DEFAULT_SET)
local Get, Enabled = F.Get, F.Enabled

local SOFT_UNIT = "softinteract"
local BOBBER_ID = 35591
local OBJECT_GUID_KIND = "^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"
local SKILL_LINE_KIND = { ore = 186, herb = 182 }
local ICON_FOR_SPELL = { herb = 2383, ore = 2580 }
local SPOT_UNIT = 1000
local SNAP_YARDS = 15
local GATHER_LOG_MAX = 400
local MINIMAP_PIN_MAX = 40
local ART_DIR = "Interface\\AddOns\\CludesUI\\media\\glimmer\\"
local TIER_COLOURS = {
    orange = { r = 1, g = 0.5, b = 0.25 },
    yellow = { r = 1, g = 1, b = 0 },
    green = { r = 0.25, g = 0.75, b = 0.25 },
    grey = { r = 0.5, g = 0.5, b = 0.5 },
    red = { r = 1, g = 0.38, b = 0.38 },
}
local BLOCKED_RGB = { r = 0.62, g = 0.62, b = 0.62 }
local QUEST_RGB = { r = 1, g = 0.82, b = 0 }
local INTERACT_CVARS = {
    SoftTargetInteract = function() return "3" end,
    SoftTargetInteractOnlyInRange = function() return "0" end,
    SoftTargetIconGameObject = function() return "1" end,
    SoftTargetInteractRange = function() return tostring(Get("range")) end,
    SoftTargetInteractArc = function() return tostring(Get("arc")) end,
}
local PLATE_SETTING = "SoftTargetNameplateInteract"

local function Simplified(v) return not (issecretvalue and issecretvalue(v)) end

-------------------------------------------------------------------------------
--  Game settings held while on
-------------------------------------------------------------------------------

local cvarRetry = CreateFrame("Frame")
local plateShown

local function Pause()
    local c = F.Cfg()
    c.held = c.held or {}
    for name, value in pairs(INTERACT_CVARS) do
        local current = C_CVar.GetCVar(name)
        local wanted = value()
        if current ~= nil and current ~= wanted then
            if c.held[name] == nil then c.held[name] = current end
            CUI.HoldCVar(name, wanted, "CludesUIForeverEssentials")
        end
    end
end

local function LetGo()
    local held = F.Read().held
    if not held then return end
    for name, value in pairs(held) do
        CUI.ReleaseCVar(name, value, "CludesUIForeverEssentials")
    end
    local plate = held[PLATE_SETTING]
    if plate then CUI.ReleaseCVar(PLATE_SETTING, plate, "CludesUIForeverEssentials") end
    F.Cfg().held = nil
    plateShown = nil
end

local function HoldInteractCVars()
    if InCombatLockdown() then
        cvarRetry:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    cvarRetry:UnregisterEvent("PLAYER_REGEN_ENABLED")
    if Enabled() then
        Pause()
    else
        LetGo()
    end
end
cvarRetry:SetScript("OnEvent", HoldInteractCVars)

-- A nameplate for the soft interact target: on while something is lit (or
-- always, with Only Highlighted off), so the effect has a frame to follow.
local function ShowOnPlate(open)
    if open == plateShown or InCombatLockdown() then return end
    plateShown = open
    local c = F.Cfg()
    c.held = c.held or {}
    if c.held[PLATE_SETTING] == nil then c.held[PLATE_SETTING] = C_CVar.GetCVar(PLATE_SETTING) or "0" end
    CUI.HoldCVar(PLATE_SETTING, open and "1" or "0", "CludesUIForeverEssentials")
end

-------------------------------------------------------------------------------
--  What the target is
-------------------------------------------------------------------------------

local CURSOR_ART = { Mine = "ore", GatherHerbs = "herb", QuestTurnIn = "quest", Quest = "quest", QuestRepeatable = "quest" }
local CURSOR_KINDS = { herb = "herb", mine = "ore", quest = "quest", important = "quest", recurring = "quest", wrapper = "quest" }
local cursorArtIds, probe

local function CursorArtIds()
    cursorArtIds = {}
    if not GetFileIDFromPath then return end
    for file, category in pairs(CURSOR_ART) do
        local ident = GetFileIDFromPath("Interface\\Cursor\\" .. file)
        if ident then cursorArtIds[ident] = { category, false } end
        ident = GetFileIDFromPath("Interface\\Cursor\\Unable" .. file)
        if ident then cursorArtIds[ident] = { category, true } end
    end
end

local function KindFromName(name)
    if type(name) ~= "string" or not Simplified(name) then return end
    name = name:lower()
    local unable = name:find("unable", 1, true) ~= nil
    for word, category in pairs(CURSOR_KINDS) do
        if name:find(word, 1, true) then return category, unable end
    end
    return nil, unable
end

-- The cursor the game would show over the unit: its category and whether
-- it is the "unable" one.
local function Cursor(unit, deferrable)
    if not SetUnitCursorTexture then return end
    if not cursorArtIds then CursorArtIds() end
    probe = probe or CreateFrame("Frame"):CreateTexture()
    if not SetUnitCursorTexture(probe, unit, nil, deferrable) then return end
    local texture = probe:GetTexture()
    if not Simplified(texture) then return end
    local known = cursorArtIds[texture]
    if known then return known[1], known[2] end
    return KindFromName(texture)
end

local function ObjectIdOf(unit)
    local guid = UnitGUID(unit)
    if not (guid and Simplified(guid)) then return end
    return tonumber(guid:match(OBJECT_GUID_KIND))
end

local function QuestText(unit)
    local data = C_TooltipInfo and C_TooltipInfo.GetUnit and C_TooltipInfo.GetUnit(unit)
    if not (data and Simplified(data) and data.lines) then return end
    local questText = Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective
    for _, line in ipairs(data.lines) do
        if line.type == questText and Simplified(line.leftText) then return line.leftText end
    end
end

local function SkillOf(index, lineId)
    if not index then return end
    local _, _, rank, _, _, _, line, modifier = GetProfessionInfo(index)
    if line == lineId then return (rank or 0) + (modifier or 0) end
end

local function SkillRank(category)
    local line = SKILL_LINE_KIND[category]
    if not line then return 0 end
    local first, second = GetProfessions()
    return SkillOf(first, line) or SkillOf(second, line) or 0
end

local function TierOf(skill, need)
    if skill < need then return "red" end
    local over = skill - need
    if over < 25 then return "orange" end
    if over < 50 then return "yellow" end
    if over < 100 then return "green" end
    return "grey"
end

local TIER_LABELS = {
    orange = "Skill-up every gather",
    yellow = "Skill-up likely",
    green = "Skill-up unlikely",
    grey = "No skill-up",
}
local function TierLabel(category, need, tier)
    if tier == "red" then
        return CUI.Lf("Requires %1$s %2$d", category == "ore" and CUI.L("Mining") or CUI.L("Herbalism"), need)
    end
    return CUI.L(TIER_LABELS[tier])
end

local function Reach(unit)
    if not UnitIsInInteractRange then return true end
    local near = UnitIsInInteractRange(unit)
    if not Simplified(near) then return false end
    return near and true or false
end

local read = {}
local function IsSkinnable(unit)
    if not Get("corpse") then return end
    local dead = UnitIsDead(unit)
    if not (Simplified(dead) and dead) then return end
    local guid = UnitGUID(unit)
    if not (guid and Simplified(guid)) then return end
    local holdsLoot, lootable = CanLootUnit(guid)
    if not (Simplified(holdsLoot) and Simplified(lootable) and holdsLoot and lootable) then return end
    wipe(read)
    read.category, read.unable, read.locked, read.ready = "corpse", false, false, Reach(unit)
    return read
end

local function IsQuestGiver(unit)
    local category, unable = Cursor(unit, true)
    if category ~= "quest" then return end
    wipe(read)
    read.category, read.unable = "giver", unable or false
    read.locked, read.ready = read.unable, Reach(unit)
    return read
end

local function ReadSoftTarget(unit)
    local object = UnitIsGameObject and UnitIsGameObject(unit)
    if not Simplified(object) then return end
    if not object then return IsSkinnable(unit) or IsQuestGiver(unit) end
    wipe(read)
    local ident = ObjectIdOf(unit)
    local node = ident and NODE_INFO[ident]
    local cursorKind, unable = Cursor(unit)
    local category = node and node[1] or (ident == BOBBER_ID and "bobber") or cursorKind
    read.id, read.unable = ident, unable or false
    if category == "ore" or category == "herb" then
        read.skill = SkillRank(category)
        read.need = node and node[2]
        if read.need then read.tier = TierOf(read.skill, read.need) end
        read.locked = read.tier == "red" or read.skill <= 0 or read.unable
    else
        local line = QuestText(unit)
        local related = C_QuestLog.UnitIsRelatedToActiveQuest and C_QuestLog.UnitIsRelatedToActiveQuest(unit)
        if line or (Simplified(related) and related) then
            category = "quest"
            read.line = line
        end
        read.locked = read.unable
    end
    if not category then return end
    read.category, read.ready = category, Reach(unit)
    return read
end

local function Color(category) return { r = Get(category .. "R"), g = Get(category .. "G"), b = Get(category .. "B") } end

-------------------------------------------------------------------------------
--  Effects (five styles, one frame)
-------------------------------------------------------------------------------

local sin, cos, sqrt, random, min, max, pi = math.sin, math.cos, math.sqrt, math.random, math.min, math.max, math.pi
local FULL_TURN = pi * 2
local BASE, DISTANT_ALPHA, BLOCKED_ALPHA, BLOCKED_SPEED = 48, 0.5, 0.55, 0.5
local FADE_SECONDS, BLEND_MODE, FLASH_SECONDS, STEP_CAP = 0.3, 0.25, 0.5, 0.1
local SPARKLE_COUNT, TRAIL_COUNT, TRAIL_LENGTH, RISE_COUNT = 14, 2, 6, 5
local CORNER_SET = { { -1, 1, 0, 1, 0, 1 }, { 1, 1, 1, 0, 0, 1 }, { 1, -1, 1, 0, 1, 0 }, { -1, -1, 0, 1, 1, 0 } }

local function TextureFor(fx, file, layer)
    local t = fx:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(ART_DIR .. file)
    t:SetBlendMode("ADD")
    t:Hide()
    return t
end

local function RespawnInfo(sparkleRef, now)
    local angle, reach = random() * FULL_TURN, sqrt(random())
    sparkleRef.x, sparkleRef.y = cos(angle) * reach * 0.9, sin(angle) * reach * 0.7
    sparkleRef.life = 0.6 + 0.8 * random()
    sparkleRef.scale = 0.5 + 0.7 * random()
    sparkleRef.angle = random() * FULL_TURN
    sparkleRef.spin = (random() - 0.5) * 2
    sparkleRef.age = now and 0 or -0.6 * random()
end

local function EaseTo(v, target, step)
    if v < target then return min(v + step, target) end
    return max(v - step, target)
end

local function Redraw(t, fx, alpha) t:SetVertexColor(fx.r, fx.g, fx.b, max(0, min(1, alpha))) end

local function Position(t, fx, x, y, w, h)
    t:ClearAllPoints()
    t:SetPoint("CENTER", fx, "CENTER", x, y)
    t:SetSize(max(w, 0.01), max(h or w, 0.01))
end

local DRAW_LAYER = {}
function DRAW_LAYER.glow(fx, a, B)
    Position(fx.glow, fx, 0, 0, B * 2.6 * (1 + 0.08 * sin(fx.time * 3)))
    Redraw(fx.glow, fx, a * 0.7)
    Position(fx.core, fx, 0, 0, B * 1.1)
    fx.core:SetVertexColor(1, 1, 1, a * 0.35 * (0.5 + 0.5 * fx.lock))
end
function DRAW_LAYER.sparkles(fx, a, B, step)
    Position(fx.glow, fx, 0, 0, B * 2.2)
    Redraw(fx.glow, fx, a * 0.25)
    for _, sparkleRef in ipairs(fx.glints) do
        sparkleRef.age = sparkleRef.age + step
        if sparkleRef.age >= sparkleRef.life then RespawnInfo(sparkleRef) end
        local age = max(sparkleRef.age, 0)
        local shine = sparkleRef.age > 0 and sin(pi * sparkleRef.age / sparkleRef.life) or 0
        Position(sparkleRef.tex, fx, sparkleRef.x * B, sparkleRef.y * B + 10 * age, B * 0.75 * sparkleRef.scale * (0.35 + 0.65 * shine))
        sparkleRef.tex:SetRotation(sparkleRef.angle + sparkleRef.spin * age)
        Redraw(sparkleRef.tex, fx, a * shine)
    end
end
function DRAW_LAYER.ring(fx, a, B)
    local gy = B * -0.35
    Position(fx.ring, fx, 0, gy, B * 2.6, B * 0.95)
    Redraw(fx.ring, fx, a)
    local rx, ry = B * 1.3, B * 0.475
    for c, tail in ipairs(fx.comets) do
        local head = fx.time * 1.6 + (c - 1) * FULL_TURN / #fx.comets
        for j, t in ipairs(tail) do
            local an, fade = head - (j - 1) * 0.09, 1 - (j - 1) / #tail
            Position(t, fx, cos(an) * rx, gy + sin(an) * ry, B * 0.42 * fade * 1.8)
            Redraw(t, fx, a * fade)
        end
    end
end
function DRAW_LAYER.beam(fx, a, B)
    local base = B * -0.35
    fx.beam:ClearAllPoints()
    fx.beam:SetPoint("BOTTOM", fx, "CENTER", 0, base)
    fx.beam:SetSize(B * 0.9, B * 3.6)
    Redraw(fx.beam, fx, a * 0.9)
    for i, t in ipairs(fx.risers) do
        local phase = (fx.time * 0.45 + i / #fx.risers) % 1
        Position(t, fx, (t.lane - 0.5) * B * 0.5, base + phase * B * 3.2, B * 0.35 * sin(pi * phase))
        t:SetVertexColor(1, 1, 1, a * sin(pi * phase))
    end
end
function DRAW_LAYER.brackets(fx, a, B)
    local far = 1 - fx.lock
    local h = B * (0.95 + 0.5 * far + far * 0.08 * sin(fx.time * 2.5))
    for i, t in ipairs(fx.brackets) do
        local c = CORNER_SET[i]
        Position(t, fx, c[1] * h, c[2] * h * 0.85, B * 0.8)
        t:SetTexCoord(c[3], c[4], c[5], c[6])
        Redraw(t, fx, a)
    end
end

local SPARKLE_PIECES = {
    glow = { "glow", "core" },
    sparkles = { "glow", "glints" },
    ring = { "ring", "comets" },
    beam = { "beam", "risers" },
    brackets = { "brackets" },
}

local function Advance(fx, elapsed)
    elapsed = min(elapsed, STEP_CAP)
    local slow = fx.locked and BLOCKED_SPEED or 1
    fx.time = fx.time + elapsed * slow
    fx.appear = EaseTo(fx.appear, 1, elapsed / FADE_SECONDS)
    fx.lock = EaseTo(fx.lock, fx.ready and 1 or 0, elapsed / BLEND_MODE)
    local a = fx.appear * fx.alpha * (DISTANT_ALPHA + (1 - DISTANT_ALPHA) * fx.lock)
    if fx.locked then a = a * BLOCKED_ALPHA end
    local B = BASE * fx.size
    DRAW_LAYER[fx.style](fx, a, B, elapsed * slow)
    if fx.burstAge then
        fx.burstAge = fx.burstAge + elapsed
        local k = fx.burstAge / FLASH_SECONDS
        if k >= 1 then
            fx.burstAge = nil
            fx.burst:Hide()
        else
            Position(fx.burst, fx, 0, 0, B * (0.8 + k * 3))
            fx.burst:SetVertexColor(1, 1, 1, (1 - k) * fx.alpha)
            fx.burst:Show()
        end
    end
end

local function NewSparkle(parent)
    local fx = CreateFrame("Frame", nil, parent)
    fx:SetSize(1, 1)
    fx.time, fx.appear, fx.lock, fx.alpha, fx.size = 0, 0, 0, 1, 1
    fx.r, fx.g, fx.b, fx.style = 1, 1, 1, "sparkles"
    fx.glow = TextureFor(fx, "glow", "BACKGROUND")
    fx.core = TextureFor(fx, "glow")
    fx.ring = TextureFor(fx, "ring", "BORDER")
    fx.beam = TextureFor(fx, "beam", "BORDER")
    fx.burst = TextureFor(fx, "ring", "OVERLAY")
    fx.glints, fx.comets, fx.risers, fx.brackets = {}, {}, {}, {}
    local sparkleTextures, trailTextures = {}, {}
    for i = 1, SPARKLE_COUNT do
        local g = { tex = TextureFor(fx, "flare", "OVERLAY") }
        RespawnInfo(g)
        fx.glints[i], sparkleTextures[i] = g, g.tex
    end
    for c = 1, TRAIL_COUNT do
        fx.comets[c] = {}
        for j = 1, TRAIL_LENGTH do
            local t = TextureFor(fx, "glow")
            fx.comets[c][j] = t
            trailTextures[#trailTextures + 1] = t
        end
    end
    for i = 1, RISE_COUNT do
        local t = TextureFor(fx, "flare", "OVERLAY")
        t.lane = i / (RISE_COUNT + 1)
        fx.risers[i] = t
    end
    for i = 1, #CORNER_SET do
        fx.brackets[i] = TextureFor(fx, "bracket")
    end
    fx.parts = {
        glow = { fx.glow },
        core = { fx.core },
        ring = { fx.ring },
        beam = { fx.beam },
        glints = sparkleTextures,
        comets = trailTextures,
        risers = fx.risers,
        brackets = fx.brackets,
    }
    fx:SetScript("OnUpdate", Advance)
    return fx
end

local function UseSparkle(fx, style, color, alpha, size, ready, locked)
    if not SPARKLE_PIECES[style] then style = "sparkles" end
    if fx.style ~= style or not fx.styled then
        fx.style, fx.styled = style, true
        for _, list in pairs(fx.parts) do
            for _, t in ipairs(list) do
                t:Hide()
            end
        end
        for _, key in ipairs(SPARKLE_PIECES[style]) do
            for _, t in ipairs(fx.parts[key]) do
                t:Show()
            end
        end
    end
    if locked then color = BLOCKED_RGB end
    fx.r, fx.g, fx.b = color.r, color.g, color.b
    fx.alpha, fx.size = alpha, size
    if ready and fx.ready == false and not locked then
        fx.burstAge = 0
        for _, sparkleRef in ipairs(fx.glints) do
            RespawnInfo(sparkleRef, true)
        end
    end
    fx.ready, fx.locked = ready and true or false, locked and true or false
end

local function BeginSparkle(fx)
    fx.appear, fx.burstAge = 0, nil
    fx.lock = fx.ready and 1 or 0
    fx.burst:Hide()
    for _, sparkleRef in ipairs(fx.glints) do
        RespawnInfo(sparkleRef)
    end
end

-------------------------------------------------------------------------------
--  Highlight on the target's nameplate
-------------------------------------------------------------------------------

local PLATE_OFFSET_Y, CARD_OFFSET_Y = -40, -6
local CARD_PIECES = { "HealthBarsContainer", "LevelFrame", "PlayerLevelDiffFrame" }
local fx, line, watch, plate, shown, cardHost
local highlightFrame = CreateFrame("Frame")

local function IsHeld()
    if InCombatLockdown() then return true end
    return Get("hideInstance") and IsInInstance() and true or false
end

local function ShowCard()
    if not cardHost then return end
    for _, name in ipairs(CARD_PIECES) do
        if cardHost[name] then cardHost[name]:SetAlpha(1) end
    end
    cardHost = nil
end

-- A unit's plate (a corpse, a quest giver): the game shows it only because
-- the soft target's plate is on, so its health bar and level step aside and
-- just the name stays over the effect (only where the plate is the game's own).
local function HideCard(to)
    local unitFrame = to.UnitFrame
    if not unitFrame then return end
    cardHost = unitFrame
    for _, name in ipairs(CARD_PIECES) do
        if unitFrame[name] then unitFrame[name]:SetAlpha(0) end
    end
end

local function StopSparkle()
    if not plate then return end
    ShowCard()
    fx:Hide()
    fx:ClearAllPoints()
    fx:SetParent(UIParent)
    watch:Hide()
    plate, shown = nil, nil
end

local function MakeSparkle()
    if fx then return end
    fx = NewSparkle(UIParent)
    fx:Hide()
    line = fx:CreateFontString(nil, "OVERLAY")
    CUI.Kit.Font(line, 12, "essentials", "OUTLINE")
    watch = CreateFrame("Frame")
    watch:Hide()
end

local function CardLine(info)
    if info.category == "quest" then return info.line, QUEST_RGB end
    if not info.tier then return end
    return TierLabel(info.category, info.need, info.tier), TIER_COLOURS[info.tier]
end

local function DrawSparkle(info)
    local color = (info.tier and Get("skillColors")) and TIER_COLOURS[info.tier] or Color(info.category)
    UseSparkle(fx, Get("style"), color, Get("brightness"), Get("size"), info.ready, info.locked)
    local text, c = CardLine(info)
    if text and Get("showLine") then
        line:SetText(text)
        line:SetTextColor(c.r, c.g, c.b)
        line:Show()
    else
        line:Hide()
    end
end

local function FixToPlate(to, info)
    fx:SetParent(to)
    local level = to:GetFrameLevel()
    if Simplified(level) then fx:SetFrameLevel(math.max(level - 1, 0)) end
    if fx.SetIgnoreParentAlpha then fx:SetIgnoreParentAlpha(true) end
    fx:ClearAllPoints()
    fx:SetPoint("CENTER", to, "CENTER", 0, PLATE_OFFSET_Y)
    if info.category == "corpse" or info.category == "giver" then HideCard(to) end
    line:ClearAllPoints()
    line:SetPoint("TOP", to, "BOTTOM", 0, CARD_OFFSET_Y)
    plate, shown = to, { ready = info.ready }
    for k, v in pairs(info) do
        shown[k] = v
    end
    DrawSparkle(shown)
    BeginSparkle(fx)
    fx:Show()
    watch:Show()
end

local function WantedNow(category) return category ~= nil and Get(category) and true or false end

local function Assess()
    if not Enabled() then return StopSparkle() end
    if IsHeld() then
        ShowOnPlate(false)
        return StopSparkle()
    end
    local info = ReadSoftTarget(SOFT_UNIT)
    if not (info and WantedNow(info.category) and not (info.locked and Get("hideLocked"))) then
        ShowOnPlate(not Get("onlyHighlighted"))
        return StopSparkle()
    end
    ShowOnPlate(true)
    local to = C_NamePlate.GetNamePlateForUnit(SOFT_UNIT)
    if not (to and Simplified(to)) then return StopSparkle() end
    if to ~= plate then
        StopSparkle()
        FixToPlate(to, info)
    else
        for k, v in pairs(info) do
            shown[k] = v
        end
        DrawSparkle(shown)
    end
end

-- Walking into reach (or out of it) brightens or dims the effect, held a
-- moment so the edge of the range does not flicker.
local watchedAt, readyAt, wantedAt = 0, nil, nil
local function WatchSoft(_, elapsed)
    watchedAt = watchedAt + elapsed
    if watchedAt < 0.15 then return end
    watchedAt = 0
    if not shown then return end
    local ready = Reach(SOFT_UNIT)
    if ready == shown.ready then
        wantedAt = nil
        return
    end
    local now = GetTime()
    if ready ~= readyAt or not wantedAt then
        readyAt, wantedAt = ready, now
    elseif now - wantedAt >= 0.15 then
        shown.ready, wantedAt = ready, nil
        DrawSparkle(shown)
    end
end

highlightFrame:SetScript("OnEvent", function(_, evt, unit)
    if evt == "PLAYER_REGEN_DISABLED" then
        ShowOnPlate(false)
        StopSparkle()
    elseif evt == "NAME_PLATE_UNIT_ADDED" then
        local soft = UnitIsUnit(unit, SOFT_UNIT)
        if not plate and not (Simplified(soft) and not soft) then Assess() end
    elseif evt == "NAME_PLATE_UNIT_REMOVED" then
        if plate and C_NamePlate.GetNamePlateForUnit(unit) == plate then StopSparkle() end
    elseif evt == "PLAYER_SOFT_INTERACT_CHANGED" then
        StopSparkle()
        Assess()
    elseif evt == "QUEST_LOG_UPDATE" or evt == "SKILL_LINES_CHANGED" then
        if plate then Assess() end
    else
        Assess()
    end
end)

local HIGHLIGHT_EVENTS = {
    "PLAYER_SOFT_INTERACT_CHANGED",
    "NAME_PLATE_UNIT_ADDED",
    "NAME_PLATE_UNIT_REMOVED",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_ENTERING_WORLD",
    "QUEST_LOG_UPDATE",
    "SKILL_LINES_CHANGED",
}

local function ApplyHighlight()
    highlightFrame:UnregisterAllEvents()
    if not Enabled() then
        if fx then StopSparkle() end
        return
    end
    MakeSparkle()
    watch:SetScript("OnUpdate", WatchSoft)
    for _, evt in ipairs(HIGHLIGHT_EVENTS) do
        highlightFrame:RegisterEvent(evt)
    end
    StopSparkle()
    Assess()
end

-------------------------------------------------------------------------------
--  Spots: where herbs and ore grow, and the ones you gathered
-------------------------------------------------------------------------------

local SPOT_TABLE
local function UnpackSpots()
    if SPOT_TABLE then return true end
    local packed = module.GLIMMER_SPOTS_PACKED
    local u = C_EncodingUtil
    if not (packed and u and u.DecodeBase64 and u.DecompressString and u.DeserializeCBOR) or InCombatLockdown() then
        return false
    end
    local success, flat = pcall(function()
        return u.DeserializeCBOR(u.DecompressString(u.DecodeBase64(packed), Enum.CompressionMethod.Deflate))
    end)
    if not success or type(flat) ~= "table" then return false end
    local all = {}
    for i = 1, #flat, 2 do
        all[flat[i]] = flat[i + 1]
    end
    SPOT_TABLE, module.GLIMMER_SPOTS_PACKED = all, nil
    return true
end

local function ShowSpot(category)
    if not Get(category) then return false end
    if not Get("myProfessions") then return true end
    return SkillRank(category) > 0
end

local function MapSpots(mapID, out)
    wipe(out)
    local all = SPOT_TABLE and SPOT_TABLE[mapID]
    if not all then return 0 end
    local want = { ore = ShowSpot("ore"), herb = ShowSpot("herb") }
    local n = 0
    for i = 1, #all, 3 do
        local node = NODE_INFO[all[i]]
        if node and want[node[1]] then
            out[n + 1], out[n + 2], out[n + 3] = all[i], all[i + 1], all[i + 2]
            n = n + 3
        end
    end
    return n / 3
end

local function NodeSkillTier(ident)
    local node = NODE_INFO[ident]
    if not node then return end
    return TierOf(SkillRank(node[1]), node[2])
end

local function NodeRGB(ident)
    local node = NODE_INFO[ident]
    local tier = Get("skillColors") and NodeSkillTier(ident)
    return tier and TIER_COLOURS[tier] or Color(node[1])
end

local function NoteGathered(mapID)
    local all = F.Read().gathered
    return all and all[mapID]
end

local function SnapToGrid(mapID, gatheredLog, ident, x, y)
    local bestX, bestY, best = x, y, SNAP_YARDS * SNAP_YARDS
    for _, e in pairs(gatheredLog) do
        if e.id == ident then
            local d = (e.x - x) ^ 2 + (e.y - y) ^ 2
            if d <= best then bestX, bestY, best = e.x, e.y, d end
        end
    end
    if best < SNAP_YARDS * SNAP_YARDS then return bestX, bestY end
    local all = SPOT_TABLE and SPOT_TABLE[mapID]
    for i = 1, all and #all or 0, 3 do
        if all[i] == ident then
            local d = (all[i + 1] - x) ^ 2 + (all[i + 2] - y) ^ 2
            if d <= best then bestX, bestY, best = all[i + 1], all[i + 2], d end
        end
    end
    return bestX, bestY
end

local function Remember(ident)
    local mapID = C_Map.GetBestMapForUnit("player")
    local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return end
    local px, py = pos:GetXY()
    if not (Simplified(px) and Simplified(py)) then return end
    local c = F.Cfg()
    c.gathered = c.gathered or {}
    local map = c.gathered[mapID] or {}
    c.gathered[mapID] = map
    local x, y = SnapToGrid(mapID, map, ident, math.floor(px * SPOT_UNIT + 0.5), math.floor(py * SPOT_UNIT + 0.5))
    local key = ("%d:%d:%d"):format(ident, x, y)
    local entry = map[key]
    if not entry then
        local count, oldest, oldestKey = 0, nil, nil
        for k, e in pairs(map) do
            count = count + 1
            if not oldest or e.last < oldest then oldest, oldestKey = e.last, k end
        end
        if count >= GATHER_LOG_MAX then map[oldestKey] = nil end
        entry = { id = ident, x = x, y = y, count = 0 }
        map[key] = entry
    end
    entry.count, entry.last = entry.count + 1, time()
    return entry
end

-------------------------------------------------------------------------------
--  Minimap spots
-------------------------------------------------------------------------------

local mini
local spots, tracked = {}, {}
local minimapFrame = CreateFrame("Frame")

local function NodeTooltip(owner, ident, extra)
    local node = NODE_INFO[ident]
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(("%s (%d)"):format(CUI.L(node[3]), node[2]), 1, 1, 1)
    local tier = NodeSkillTier(ident)
    if tier then
        local c = TIER_COLOURS[tier]
        GameTooltip:AddLine(TierLabel(node[1], node[2], tier), c.r, c.g, c.b)
    end
    if extra then
        local m = CUI.Kit.Palette.muted
        GameTooltip:AddLine(extra, m[1], m[2], m[3])
    end
    GameTooltip:Show()
end

local function NewMinimapPin()
    local pin = CreateFrame("Frame", nil, Minimap)
    pin.ring = pin:CreateTexture(nil, "BACKGROUND")
    pin.ring:SetTexture(ART_DIR .. "ring")
    pin.ring:SetPoint("CENTER")
    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetPoint("CENTER")
    pin.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    pin:EnableMouse(true)
    pin:SetScript("OnEnter", function(self) NodeTooltip(self, self.id) end)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return pin
end

-- With Find Herbs / Find Minerals tracking, the icon moves to the ring's
-- corner so the game's own dot shows inside it when the node is up.
local function DrawMinimapPin(pin, list, i)
    local ident = list[i * 3 - 2]
    local node = NODE_INFO[ident]
    local size = Get("minimapSize")
    pin.id = ident
    pin:SetSize(size, size)
    pin.ring:SetSize(size * 1.6, size * 1.6)
    pin.icon:ClearAllPoints()
    if tracked[node[1]] then
        pin.icon:SetPoint("CENTER", size * 0.57, -size * 0.57)
        pin.icon:SetSize(size * 0.45, size * 0.45)
    else
        pin.icon:SetPoint("CENTER")
        pin.icon:SetSize(size * 0.7, size * 0.7)
    end
    pin.icon:SetTexture(C_Spell.GetSpellTexture(ICON_FOR_SPELL[node[1]]))
    local c = NodeRGB(ident)
    pin.ring:SetVertexColor(c.r, c.g, c.b)
end

local function Follow()
    wipe(tracked)
    if not (C_Minimap and C_Minimap.GetNumTrackingTypes) then return end
    for i = 1, C_Minimap.GetNumTrackingTypes() do
        local info = C_Minimap.GetTrackingInfo(i)
        if info and info.active then
            for category, spell in pairs(ICON_FOR_SPELL) do
                if info.spellID == spell then tracked[category] = true end
            end
        end
    end
end

local function RefreshMinimapPins()
    local on = Enabled() and Get("minimapIcons") and (ShowSpot("ore") or ShowSpot("herb"))
    if not on or not UnpackSpots() then
        if mini then mini:Set(nil) end
        return
    end
    Follow()
    mini = mini or module.MinimapLayer({
        max = MINIMAP_PIN_MAX,
        new = NewMinimapPin,
        paint = DrawMinimapPin,
        xy = function(list, i) return list[i * 3 - 1] / SPOT_UNIT, list[i * 3] / SPOT_UNIT end,
    })
    local mapID = C_Map.GetBestMapForUnit("player")
    mini:Set(mapID, spots, mapID and MapSpots(mapID, spots) or 0)
end
minimapFrame:SetScript("OnEvent", RefreshMinimapPins)

local function ApplyMinimapPins()
    minimapFrame:UnregisterAllEvents()
    if Enabled() and Get("minimapIcons") and module.MinimapLayer then
        for _, evt in ipairs({
            "ZONE_CHANGED_NEW_AREA",
            "ZONE_CHANGED",
            "ZONE_CHANGED_INDOORS",
            "PLAYER_ENTERING_WORLD",
            "SKILL_LINES_CHANGED",
            "PLAYER_REGEN_ENABLED",
            "MINIMAP_UPDATE_TRACKING",
        }) do
            minimapFrame:RegisterEvent(evt)
        end
    end
    if module.MinimapLayer and IsLoggedIn() then RefreshMinimapPins() end
end

-------------------------------------------------------------------------------
--  Gathered on the world map
-------------------------------------------------------------------------------

local provider, layer, added, waiter, lastSoft
local mapPinPool, mapPinsUsed = {}, 0
local lootFrame = CreateFrame("Frame")

local function ClearMapPins()
    for i = 1, mapPinsUsed do
        mapPinPool[i]:Hide()
    end
    mapPinsUsed = 0
end

local function MapLayer(p)
    local canvas = layer:GetParent()
    local wid, hgt = canvas:GetSize()
    local cs = canvas:GetScale()
    p:SetScale(1 / cs)
    p:ClearAllPoints()
    p:SetPoint("CENTER", canvas, "TOPLEFT", p.x * wid * cs, -p.y * hgt * cs)
end

local function MapPinAt(i)
    local p = mapPinPool[i]
    if p then return p end
    p = CreateFrame("Frame", nil, layer)
    p.ring = p:CreateTexture(nil, "BACKGROUND")
    p.ring:SetTexture(ART_DIR .. "ring")
    p.ring:SetPoint("TOPLEFT", -4, 4)
    p.ring:SetPoint("BOTTOMRIGHT", 4, -4)
    p.icon = p:CreateTexture(nil, "ARTWORK")
    p.icon:SetAllPoints()
    p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    p:EnableMouse(true)
    p:SetScript("OnEnter", function(self)
        NodeTooltip(self, self.entry.id, CUI.Lf("Gathered %1$d times.", self.entry.count))
    end)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mapPinPool[i] = p
    return p
end

local function DrawMapPins()
    ClearMapPins()
    if not (Enabled() and Get("gatheredPins")) then return end
    local mapID = WorldMapFrame:GetMapID()
    for _, entry in pairs(mapID and NoteGathered(mapID) or {}) do
        local node = NODE_INFO[entry.id]
        if node and Get(node[1]) then
            mapPinsUsed = mapPinsUsed + 1
            local p = MapPinAt(mapPinsUsed)
            local size = Get("gatheredPinSize")
            p.entry, p.x, p.y = entry, entry.x / SPOT_UNIT, entry.y / SPOT_UNIT
            p:SetSize(size, size)
            p.icon:SetTexture(C_Spell.GetSpellTexture(ICON_FOR_SPELL[node[1]]))
            local c = NodeRGB(entry.id)
            p.ring:SetVertexColor(c.r, c.g, c.b)
            MapLayer(p)
            p:Show()
        end
    end
end

local function MakeMapLayer()
    layer = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer.Child)
    layer:SetAllPoints()
    layer:SetFrameLevel(WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_AREA_POI"))
    provider = CreateFromMixins(MapCanvasDataProviderMixin)
    provider.OnMapChanged = DrawMapPins
    provider.RefreshAllData = DrawMapPins
    provider.RemoveAllData = ClearMapPins
    provider.OnCanvasScaleChanged = function()
        for i = 1, mapPinsUsed do
            MapLayer(mapPinPool[i])
        end
    end
    provider.OnGlobalAlphaChanged = function(self) layer:SetAlpha(self:GetMap():GetGlobalAlpha()) end
end

-- A loot window from a herb or vein (by the loot's source GUID) notes it.
local function OnLooted()
    for slot = 1, GetNumLootItems() do
        local sources = { GetLootSourceInfo(slot) }
        for i = 1, #sources, 2 do
            local guid = sources[i]
            if Simplified(guid) and type(guid) == "string" then
                local ident = tonumber(guid:match(OBJECT_GUID_KIND))
                local node = ident and NODE_INFO[ident]
                if node and (node[1] == "ore" or node[1] == "herb") then
                    if guid ~= lastSoft then
                        lastSoft = guid
                        if Remember(ident) and WorldMapFrame and WorldMapFrame:IsShown() then DrawMapPins() end
                    end
                    return
                end
            end
        end
    end
end
lootFrame:SetScript("OnEvent", OnLooted)

local function ApplyMapPins()
    local on = Enabled() and Get("gatheredPins")
    if on then
        lootFrame:RegisterEvent("LOOT_READY")
    else
        lootFrame:UnregisterEvent("LOOT_READY")
    end
    if not on then
        if added then
            WorldMapFrame:RemoveDataProvider(provider)
            added = false
        end
        if layer then ClearMapPins() end
        return
    end
    if not provider then
        if not C_AddOns.IsAddOnLoaded("Blizzard_WorldMap") then
            if not waiter then
                waiter = CreateFrame("Frame")
                waiter:SetScript("OnEvent", function(self, _, name)
                    if name ~= "Blizzard_WorldMap" then return end
                    self:UnregisterEvent("ADDON_LOADED")
                    ApplyMapPins()
                end)
            end
            waiter:RegisterEvent("ADDON_LOADED")
            return
        end
        MakeMapLayer()
    end
    if not added then
        WorldMapFrame:AddDataProvider(provider)
        added = true
    end
    if WorldMapFrame:IsShown() then DrawMapPins() end
end

-------------------------------------------------------------------------------

local function Apply()
    HoldInteractCVars()
    ApplyHighlight()
    ApplyMinimapPins()
    ApplyMapPins()
end

CUI._Glimmer = {
    Get = Get,
    Cfg = F.Cfg,
    Apply = Apply,
    Categories = KIND_LIST,
    Read = ReadSoftTarget,
    Record = Remember,
    Gathered = NoteGathered,
    -- The effect frame and its line (tests).
    Fx = function() return fx, line end,
    -- For Zone Info: the herbs and ore that grow in a zone, each once, by
    -- skill: { kind, need, name } (nil while the spots cannot be read yet).
    ZoneNodes = function(mapID)
        if not UnpackSpots() then return nil end
        local list, seen = {}, {}
        local all = SPOT_TABLE[mapID]
        for i = 1, all and #all or 0, 3 do
            local node = NODE_INFO[all[i]]
            local key = node and (node[1] .. ":" .. node[3])
            if node and (node[1] == "herb" or node[1] == "ore") and not seen[key] then
                seen[key] = true
                list[#list + 1] = { kind = node[1], need = node[2], name = node[3] }
            end
        end
        table.sort(list, function(a, b)
            if a.need ~= b.need then return a.need < b.need end
            return a.name < b.name
        end)
        return list
    end,
    Skill = SkillRank,
}

F.Start(Apply)
