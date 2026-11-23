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

local NODES = module.GLIMMER_NODES or {}
local CATEGORIES = { "ore", "herb", "quest", "giver", "chest", "bobber", "corpse" }

local DEFAULTS = {
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
local F = module.Feature("glimmer", DEFAULTS)
local Get, Enabled = F.Get, F.Enabled

local UNIT = "softinteract"
local BOBBER = 35591
local GUID_OBJECT = "^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"
local PROFESSION_OF = { ore = 186, herb = 182 }
local ICON_SPELL = { herb = 2383, ore = 2580 }
local SPOT_SCALE = 1000
local SNAP = 15
local MAX_GATHERED = 400
local MINIMAP_MAX = 40
local MEDIA = "Interface\\AddOns\\CludesUI\\media\\glimmer\\"
local TIER_RGB = {
    orange = { r = 1, g = 0.5, b = 0.25 },
    yellow = { r = 1, g = 1, b = 0 },
    green = { r = 0.25, g = 0.75, b = 0.25 },
    grey = { r = 0.5, g = 0.5, b = 0.5 },
    red = { r = 1, g = 0.38, b = 0.38 },
}
local LOCKED_RGB = { r = 0.62, g = 0.62, b = 0.62 }
local QUEST_LINE_RGB = { r = 1, g = 0.82, b = 0 }
local SOFT_CVARS = {
    SoftTargetInteract = function() return "3" end,
    SoftTargetInteractOnlyInRange = function() return "0" end,
    SoftTargetIconGameObject = function() return "1" end,
    SoftTargetInteractRange = function() return tostring(Get("range")) end,
    SoftTargetInteractArc = function() return tostring(Get("arc")) end,
}
local PLATE_CVAR = "SoftTargetNameplateInteract"

local function Plain(v) return not (issecretvalue and issecretvalue(v)) end

-------------------------------------------------------------------------------
--  Game settings held while on
-------------------------------------------------------------------------------

local cvarWait = CreateFrame("Frame")
local plateOpen

local function Hold()
    local c = F.Cfg()
    c.held = c.held or {}
    for name, value in pairs(SOFT_CVARS) do
        local current = C_CVar.GetCVar(name)
        local wanted = value()
        if current ~= nil and current ~= wanted then
            if c.held[name] == nil then c.held[name] = current end
            CUI.HoldCVar(name, wanted, "CludesUIForeverEssentials")
        end
    end
end

local function Release()
    local held = F.Read().held
    if not held then return end
    for name, value in pairs(held) do
        CUI.ReleaseCVar(name, value, "CludesUIForeverEssentials")
    end
    local plate = held[PLATE_CVAR]
    if plate then CUI.ReleaseCVar(PLATE_CVAR, plate, "CludesUIForeverEssentials") end
    F.Cfg().held = nil
    plateOpen = nil
end

local function ApplyCVars()
    if InCombatLockdown() then
        cvarWait:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    cvarWait:UnregisterEvent("PLAYER_REGEN_ENABLED")
    if Enabled() then
        Hold()
    else
        Release()
    end
end
cvarWait:SetScript("OnEvent", ApplyCVars)

-- A nameplate for the soft interact target: on while something is lit (or
-- always, with Only Highlighted off), so the effect has a frame to follow.
local function SetPlate(open)
    if open == plateOpen or InCombatLockdown() then return end
    plateOpen = open
    local c = F.Cfg()
    c.held = c.held or {}
    if c.held[PLATE_CVAR] == nil then c.held[PLATE_CVAR] = C_CVar.GetCVar(PLATE_CVAR) or "0" end
    CUI.HoldCVar(PLATE_CVAR, open and "1" or "0", "CludesUIForeverEssentials")
end

-------------------------------------------------------------------------------
--  What the target is
-------------------------------------------------------------------------------

local CURSOR_FILES = { Mine = "ore", GatherHerbs = "herb", QuestTurnIn = "quest", Quest = "quest", QuestRepeatable = "quest" }
local CURSOR_WORDS = { herb = "herb", mine = "ore", quest = "quest", important = "quest", recurring = "quest", wrapper = "quest" }
local cursorIDs, probe

local function CursorIDs()
    cursorIDs = {}
    if not GetFileIDFromPath then return end
    for file, category in pairs(CURSOR_FILES) do
        local ident = GetFileIDFromPath("Interface\\Cursor\\" .. file)
        if ident then cursorIDs[ident] = { category, false } end
        ident = GetFileIDFromPath("Interface\\Cursor\\Unable" .. file)
        if ident then cursorIDs[ident] = { category, true } end
    end
end

local function FromName(name)
    if type(name) ~= "string" or not Plain(name) then return end
    name = name:lower()
    local unable = name:find("unable", 1, true) ~= nil
    for word, category in pairs(CURSOR_WORDS) do
        if name:find(word, 1, true) then return category, unable end
    end
    return nil, unable
end

-- The cursor the game would show over the unit: its category and whether
-- it is the "unable" one.
local function Cursor(unit, lowPriority)
    if not SetUnitCursorTexture then return end
    if not cursorIDs then CursorIDs() end
    probe = probe or CreateFrame("Frame"):CreateTexture()
    if not SetUnitCursorTexture(probe, unit, nil, lowPriority) then return end
    local texture = probe:GetTexture()
    if not Plain(texture) then return end
    local known = cursorIDs[texture]
    if known then return known[1], known[2] end
    return FromName(texture)
end

local function ObjectID(unit)
    local guid = UnitGUID(unit)
    if not (guid and Plain(guid)) then return end
    return tonumber(guid:match(GUID_OBJECT))
end

local function QuestLine(unit)
    local data = C_TooltipInfo and C_TooltipInfo.GetUnit and C_TooltipInfo.GetUnit(unit)
    if not (data and Plain(data) and data.lines) then return end
    local questLine = Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective
    for _, line in ipairs(data.lines) do
        if line.type == questLine and Plain(line.leftText) then return line.leftText end
    end
end

local function SkillAt(index, skillLine)
    if not index then return end
    local _, _, rank, _, _, _, line, modifier = GetProfessionInfo(index)
    if line == skillLine then return (rank or 0) + (modifier or 0) end
end

local function Skill(category)
    local line = PROFESSION_OF[category]
    if not line then return 0 end
    local first, second = GetProfessions()
    return SkillAt(first, line) or SkillAt(second, line) or 0
end

local function Tier(skill, need)
    if skill < need then return "red" end
    local over = skill - need
    if over < 25 then return "orange" end
    if over < 50 then return "yellow" end
    if over < 100 then return "green" end
    return "grey"
end

local TIER_TEXT = {
    orange = "Skill-up every gather",
    yellow = "Skill-up likely",
    green = "Skill-up unlikely",
    grey = "No skill-up",
}
local function TierText(category, need, tier)
    if tier == "red" then
        return CUI.Lf("Requires %1$s %2$d", category == "ore" and CUI.L("Mining") or CUI.L("Herbalism"), need)
    end
    return CUI.L(TIER_TEXT[tier])
end

local function Reach(unit)
    if not UnitIsInInteractRange then return true end
    local near = UnitIsInInteractRange(unit)
    if not Plain(near) then return false end
    return near and true or false
end

local read = {}
local function Corpse(unit)
    if not Get("corpse") then return end
    local dead = UnitIsDead(unit)
    if not (Plain(dead) and dead) then return end
    local guid = UnitGUID(unit)
    if not (guid and Plain(guid)) then return end
    local hasLoot, canLoot = CanLootUnit(guid)
    if not (Plain(hasLoot) and Plain(canLoot) and hasLoot and canLoot) then return end
    wipe(read)
    read.category, read.unable, read.locked, read.ready = "corpse", false, false, Reach(unit)
    return read
end

local function QuestGiver(unit)
    local category, unable = Cursor(unit, true)
    if category ~= "quest" then return end
    wipe(read)
    read.category, read.unable = "giver", unable or false
    read.locked, read.ready = read.unable, Reach(unit)
    return read
end

local function ReadTarget(unit)
    local object = UnitIsGameObject and UnitIsGameObject(unit)
    if not Plain(object) then return end
    if not object then return Corpse(unit) or QuestGiver(unit) end
    wipe(read)
    local ident = ObjectID(unit)
    local node = ident and NODES[ident]
    local cursorCategory, unable = Cursor(unit)
    local category = node and node[1] or (ident == BOBBER and "bobber") or cursorCategory
    read.id, read.unable = ident, unable or false
    if category == "ore" or category == "herb" then
        read.skill = Skill(category)
        read.need = node and node[2]
        if read.need then read.tier = Tier(read.skill, read.need) end
        read.locked = read.tier == "red" or read.skill <= 0 or read.unable
    else
        local line = QuestLine(unit)
        local related = C_QuestLog.UnitIsRelatedToActiveQuest and C_QuestLog.UnitIsRelatedToActiveQuest(unit)
        if line or (Plain(related) and related) then
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
local TWO_PI = pi * 2
local BASE, FAR_ALPHA, LOCKED_ALPHA, LOCKED_SPEED = 48, 0.5, 0.55, 0.5
local FADE, BLEND, BURST_TIME, MAX_STEP = 0.3, 0.25, 0.5, 0.1
local GLINTS, COMETS, TAIL, RISERS = 14, 2, 6, 5
local CORNERS = { { -1, 1, 0, 1, 0, 1 }, { 1, 1, 1, 0, 0, 1 }, { 1, -1, 1, 0, 1, 0 }, { -1, -1, 0, 1, 1, 0 } }

local function Tex(fx, file, layer)
    local t = fx:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(MEDIA .. file)
    t:SetBlendMode("ADD")
    t:Hide()
    return t
end

local function Respawn(glint, now)
    local angle, reach = random() * TWO_PI, sqrt(random())
    glint.x, glint.y = cos(angle) * reach * 0.9, sin(angle) * reach * 0.7
    glint.life = 0.6 + 0.8 * random()
    glint.scale = 0.5 + 0.7 * random()
    glint.angle = random() * TWO_PI
    glint.spin = (random() - 0.5) * 2
    glint.age = now and 0 or -0.6 * random()
end

local function Approach(v, target, step)
    if v < target then return min(v + step, target) end
    return max(v - step, target)
end

local function Paint(t, fx, alpha) t:SetVertexColor(fx.r, fx.g, fx.b, max(0, min(1, alpha))) end

local function Place(t, fx, x, y, w, h)
    t:ClearAllPoints()
    t:SetPoint("CENTER", fx, "CENTER", x, y)
    t:SetSize(max(w, 0.01), max(h or w, 0.01))
end

local DRAW = {}
function DRAW.glow(fx, a, B)
    Place(fx.glow, fx, 0, 0, B * 2.6 * (1 + 0.08 * sin(fx.time * 3)))
    Paint(fx.glow, fx, a * 0.7)
    Place(fx.core, fx, 0, 0, B * 1.1)
    fx.core:SetVertexColor(1, 1, 1, a * 0.35 * (0.5 + 0.5 * fx.lock))
end
function DRAW.sparkles(fx, a, B, step)
    Place(fx.glow, fx, 0, 0, B * 2.2)
    Paint(fx.glow, fx, a * 0.25)
    for _, glint in ipairs(fx.glints) do
        glint.age = glint.age + step
        if glint.age >= glint.life then Respawn(glint) end
        local age = max(glint.age, 0)
        local shine = glint.age > 0 and sin(pi * glint.age / glint.life) or 0
        Place(glint.tex, fx, glint.x * B, glint.y * B + 10 * age, B * 0.75 * glint.scale * (0.35 + 0.65 * shine))
        glint.tex:SetRotation(glint.angle + glint.spin * age)
        Paint(glint.tex, fx, a * shine)
    end
end
function DRAW.ring(fx, a, B)
    local gy = B * -0.35
    Place(fx.ring, fx, 0, gy, B * 2.6, B * 0.95)
    Paint(fx.ring, fx, a)
    local rx, ry = B * 1.3, B * 0.475
    for c, tail in ipairs(fx.comets) do
        local head = fx.time * 1.6 + (c - 1) * TWO_PI / #fx.comets
        for j, t in ipairs(tail) do
            local an, fade = head - (j - 1) * 0.09, 1 - (j - 1) / #tail
            Place(t, fx, cos(an) * rx, gy + sin(an) * ry, B * 0.42 * fade * 1.8)
            Paint(t, fx, a * fade)
        end
    end
end
function DRAW.beam(fx, a, B)
    local base = B * -0.35
    fx.beam:ClearAllPoints()
    fx.beam:SetPoint("BOTTOM", fx, "CENTER", 0, base)
    fx.beam:SetSize(B * 0.9, B * 3.6)
    Paint(fx.beam, fx, a * 0.9)
    for i, t in ipairs(fx.risers) do
        local phase = (fx.time * 0.45 + i / #fx.risers) % 1
        Place(t, fx, (t.lane - 0.5) * B * 0.5, base + phase * B * 3.2, B * 0.35 * sin(pi * phase))
        t:SetVertexColor(1, 1, 1, a * sin(pi * phase))
    end
end
function DRAW.brackets(fx, a, B)
    local far = 1 - fx.lock
    local h = B * (0.95 + 0.5 * far + far * 0.08 * sin(fx.time * 2.5))
    for i, t in ipairs(fx.brackets) do
        local c = CORNERS[i]
        Place(t, fx, c[1] * h, c[2] * h * 0.85, B * 0.8)
        t:SetTexCoord(c[3], c[4], c[5], c[6])
        Paint(t, fx, a)
    end
end

local PARTS = {
    glow = { "glow", "core" },
    sparkles = { "glow", "glints" },
    ring = { "ring", "comets" },
    beam = { "beam", "risers" },
    brackets = { "brackets" },
}

local function Step(fx, elapsed)
    elapsed = min(elapsed, MAX_STEP)
    local slow = fx.locked and LOCKED_SPEED or 1
    fx.time = fx.time + elapsed * slow
    fx.appear = Approach(fx.appear, 1, elapsed / FADE)
    fx.lock = Approach(fx.lock, fx.ready and 1 or 0, elapsed / BLEND)
    local a = fx.appear * fx.alpha * (FAR_ALPHA + (1 - FAR_ALPHA) * fx.lock)
    if fx.locked then a = a * LOCKED_ALPHA end
    local B = BASE * fx.size
    DRAW[fx.style](fx, a, B, elapsed * slow)
    if fx.burstAge then
        fx.burstAge = fx.burstAge + elapsed
        local k = fx.burstAge / BURST_TIME
        if k >= 1 then
            fx.burstAge = nil
            fx.burst:Hide()
        else
            Place(fx.burst, fx, 0, 0, B * (0.8 + k * 3))
            fx.burst:SetVertexColor(1, 1, 1, (1 - k) * fx.alpha)
            fx.burst:Show()
        end
    end
end

local function NewEffect(parent)
    local fx = CreateFrame("Frame", nil, parent)
    fx:SetSize(1, 1)
    fx.time, fx.appear, fx.lock, fx.alpha, fx.size = 0, 0, 0, 1, 1
    fx.r, fx.g, fx.b, fx.style = 1, 1, 1, "sparkles"
    fx.glow = Tex(fx, "glow", "BACKGROUND")
    fx.core = Tex(fx, "glow")
    fx.ring = Tex(fx, "ring", "BORDER")
    fx.beam = Tex(fx, "beam", "BORDER")
    fx.burst = Tex(fx, "ring", "OVERLAY")
    fx.glints, fx.comets, fx.risers, fx.brackets = {}, {}, {}, {}
    local glintTex, cometTex = {}, {}
    for i = 1, GLINTS do
        local g = { tex = Tex(fx, "flare", "OVERLAY") }
        Respawn(g)
        fx.glints[i], glintTex[i] = g, g.tex
    end
    for c = 1, COMETS do
        fx.comets[c] = {}
        for j = 1, TAIL do
            local t = Tex(fx, "glow")
            fx.comets[c][j] = t
            cometTex[#cometTex + 1] = t
        end
    end
    for i = 1, RISERS do
        local t = Tex(fx, "flare", "OVERLAY")
        t.lane = i / (RISERS + 1)
        fx.risers[i] = t
    end
    for i = 1, #CORNERS do
        fx.brackets[i] = Tex(fx, "bracket")
    end
    fx.parts = {
        glow = { fx.glow },
        core = { fx.core },
        ring = { fx.ring },
        beam = { fx.beam },
        glints = glintTex,
        comets = cometTex,
        risers = fx.risers,
        brackets = fx.brackets,
    }
    fx:SetScript("OnUpdate", Step)
    return fx
end

local function SetEffect(fx, style, color, alpha, size, ready, locked)
    if not PARTS[style] then style = "sparkles" end
    if fx.style ~= style or not fx.styled then
        fx.style, fx.styled = style, true
        for _, list in pairs(fx.parts) do
            for _, t in ipairs(list) do
                t:Hide()
            end
        end
        for _, key in ipairs(PARTS[style]) do
            for _, t in ipairs(fx.parts[key]) do
                t:Show()
            end
        end
    end
    if locked then color = LOCKED_RGB end
    fx.r, fx.g, fx.b = color.r, color.g, color.b
    fx.alpha, fx.size = alpha, size
    if ready and fx.ready == false and not locked then
        fx.burstAge = 0
        for _, glint in ipairs(fx.glints) do
            Respawn(glint, true)
        end
    end
    fx.ready, fx.locked = ready and true or false, locked and true or false
end

local function StartEffect(fx)
    fx.appear, fx.burstAge = 0, nil
    fx.lock = fx.ready and 1 or 0
    fx.burst:Hide()
    for _, glint in ipairs(fx.glints) do
        Respawn(glint)
    end
end

-------------------------------------------------------------------------------
--  Highlight on the target's nameplate
-------------------------------------------------------------------------------

local PLATE_Y, LINE_Y = -40, -6
local BAR_PARTS = { "HealthBarsContainer", "LevelFrame", "PlayerLevelDiffFrame" }
local fx, line, watch, plate, shown, barOwner
local hlEvents = CreateFrame("Frame")

local function Paused()
    if InCombatLockdown() then return true end
    return Get("hideInstance") and IsInInstance() and true or false
end

local function ShowBar()
    if not barOwner then return end
    for _, name in ipairs(BAR_PARTS) do
        if barOwner[name] then barOwner[name]:SetAlpha(1) end
    end
    barOwner = nil
end

-- A corpse's plate: its health bar and level step aside under the effect
-- (only where the plate is the game's own).
local function HideBar(to)
    local unitFrame = to.UnitFrame
    if not unitFrame then return end
    barOwner = unitFrame
    for _, name in ipairs(BAR_PARTS) do
        if unitFrame[name] then unitFrame[name]:SetAlpha(0) end
    end
end

local function ReleaseFx()
    if not plate then return end
    ShowBar()
    fx:Hide()
    fx:ClearAllPoints()
    fx:SetParent(UIParent)
    watch:Hide()
    plate, shown = nil, nil
end

local function BuildFx()
    if fx then return end
    fx = NewEffect(UIParent)
    fx:Hide()
    line = fx:CreateFontString(nil, "OVERLAY")
    CUI.Kit.Font(line, 12, "essentials", "OUTLINE")
    watch = CreateFrame("Frame")
    watch:Hide()
end

local function LineFor(info)
    if info.category == "quest" then return info.line, QUEST_LINE_RGB end
    if not info.tier then return end
    return TierText(info.category, info.need, info.tier), TIER_RGB[info.tier]
end

local function PaintFx(info)
    local color = (info.tier and Get("skillColors")) and TIER_RGB[info.tier] or Color(info.category)
    SetEffect(fx, Get("style"), color, Get("brightness"), Get("size"), info.ready, info.locked)
    local text, c = LineFor(info)
    if text and Get("showLine") then
        line:SetText(text)
        line:SetTextColor(c.r, c.g, c.b)
        line:Show()
    else
        line:Hide()
    end
end

local function Attach(to, info)
    fx:SetParent(to)
    local level = to:GetFrameLevel()
    if Plain(level) then fx:SetFrameLevel(math.max(level - 1, 0)) end
    if fx.SetIgnoreParentAlpha then fx:SetIgnoreParentAlpha(true) end
    fx:ClearAllPoints()
    fx:SetPoint("CENTER", to, "CENTER", 0, PLATE_Y)
    if info.category == "corpse" then HideBar(to) end
    line:ClearAllPoints()
    line:SetPoint("TOP", to, "BOTTOM", 0, LINE_Y)
    plate, shown = to, { ready = info.ready }
    for k, v in pairs(info) do
        shown[k] = v
    end
    PaintFx(shown)
    StartEffect(fx)
    fx:Show()
    watch:Show()
end

local function Wanted(category) return category ~= nil and Get(category) and true or false end

local function Evaluate()
    if not Enabled() then return ReleaseFx() end
    if Paused() then
        SetPlate(false)
        return ReleaseFx()
    end
    local info = ReadTarget(UNIT)
    if not (info and Wanted(info.category) and not (info.locked and Get("hideLocked"))) then
        SetPlate(not Get("onlyHighlighted"))
        return ReleaseFx()
    end
    SetPlate(true)
    local to = C_NamePlate.GetNamePlateForUnit(UNIT)
    if not (to and Plain(to)) then return ReleaseFx() end
    if to ~= plate then
        ReleaseFx()
        Attach(to, info)
    else
        for k, v in pairs(info) do
            shown[k] = v
        end
        PaintFx(shown)
    end
end

-- Walking into reach (or out of it) brightens or dims the effect, held a
-- moment so the edge of the range does not flicker.
local watchSince, wantReady, wantSince = 0, nil, nil
local function Watch(_, elapsed)
    watchSince = watchSince + elapsed
    if watchSince < 0.15 then return end
    watchSince = 0
    if not shown then return end
    local ready = Reach(UNIT)
    if ready == shown.ready then
        wantSince = nil
        return
    end
    local now = GetTime()
    if ready ~= wantReady or not wantSince then
        wantReady, wantSince = ready, now
    elseif now - wantSince >= 0.15 then
        shown.ready, wantSince = ready, nil
        PaintFx(shown)
    end
end

hlEvents:SetScript("OnEvent", function(_, evt, unit)
    if evt == "PLAYER_REGEN_DISABLED" then
        SetPlate(false)
        ReleaseFx()
    elseif evt == "NAME_PLATE_UNIT_ADDED" then
        local soft = UnitIsUnit(unit, UNIT)
        if not plate and not (Plain(soft) and not soft) then Evaluate() end
    elseif evt == "NAME_PLATE_UNIT_REMOVED" then
        if plate and C_NamePlate.GetNamePlateForUnit(unit) == plate then ReleaseFx() end
    elseif evt == "PLAYER_SOFT_INTERACT_CHANGED" then
        ReleaseFx()
        Evaluate()
    elseif evt == "QUEST_LOG_UPDATE" or evt == "SKILL_LINES_CHANGED" then
        if plate then Evaluate() end
    else
        Evaluate()
    end
end)

local HL_EVENTS = {
    "PLAYER_SOFT_INTERACT_CHANGED",
    "NAME_PLATE_UNIT_ADDED",
    "NAME_PLATE_UNIT_REMOVED",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_ENTERING_WORLD",
    "QUEST_LOG_UPDATE",
    "SKILL_LINES_CHANGED",
}

local function HighlightApply()
    hlEvents:UnregisterAllEvents()
    if not Enabled() then
        if fx then ReleaseFx() end
        return
    end
    BuildFx()
    watch:SetScript("OnUpdate", Watch)
    for _, evt in ipairs(HL_EVENTS) do
        hlEvents:RegisterEvent(evt)
    end
    ReleaseFx()
    Evaluate()
end

-------------------------------------------------------------------------------
--  Spots: where herbs and ore grow, and the ones you gathered
-------------------------------------------------------------------------------

local SPOTS
local function LoadSpots()
    if SPOTS then return true end
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
    SPOTS, module.GLIMMER_SPOTS_PACKED = all, nil
    return true
end

local function SpotWanted(category)
    if not Get(category) then return false end
    if not Get("myProfessions") then return true end
    return Skill(category) > 0
end

local function SpotsFor(mapID, out)
    wipe(out)
    local all = SPOTS and SPOTS[mapID]
    if not all then return 0 end
    local want = { ore = SpotWanted("ore"), herb = SpotWanted("herb") }
    local n = 0
    for i = 1, #all, 3 do
        local node = NODES[all[i]]
        if node and want[node[1]] then
            out[n + 1], out[n + 2], out[n + 3] = all[i], all[i + 1], all[i + 2]
            n = n + 3
        end
    end
    return n / 3
end

local function NodeTier(ident)
    local node = NODES[ident]
    if not node then return end
    return Tier(Skill(node[1]), node[2])
end

local function NodeColor(ident)
    local node = NODES[ident]
    local tier = Get("skillColors") and NodeTier(ident)
    return tier and TIER_RGB[tier] or Color(node[1])
end

local function Gathered(mapID)
    local all = F.Read().gathered
    return all and all[mapID]
end

local function Snap(mapID, gathered, ident, x, y)
    local bestX, bestY, best = x, y, SNAP * SNAP
    for _, e in pairs(gathered) do
        if e.id == ident then
            local d = (e.x - x) ^ 2 + (e.y - y) ^ 2
            if d <= best then bestX, bestY, best = e.x, e.y, d end
        end
    end
    if best < SNAP * SNAP then return bestX, bestY end
    local all = SPOTS and SPOTS[mapID]
    for i = 1, all and #all or 0, 3 do
        if all[i] == ident then
            local d = (all[i + 1] - x) ^ 2 + (all[i + 2] - y) ^ 2
            if d <= best then bestX, bestY, best = all[i + 1], all[i + 2], d end
        end
    end
    return bestX, bestY
end

local function Record(ident)
    local mapID = C_Map.GetBestMapForUnit("player")
    local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return end
    local px, py = pos:GetXY()
    if not (Plain(px) and Plain(py)) then return end
    local c = F.Cfg()
    c.gathered = c.gathered or {}
    local map = c.gathered[mapID] or {}
    c.gathered[mapID] = map
    local x, y = Snap(mapID, map, ident, math.floor(px * SPOT_SCALE + 0.5), math.floor(py * SPOT_SCALE + 0.5))
    local key = ("%d:%d:%d"):format(ident, x, y)
    local entry = map[key]
    if not entry then
        local count, oldest, oldestKey = 0, nil, nil
        for k, e in pairs(map) do
            count = count + 1
            if not oldest or e.last < oldest then oldest, oldestKey = e.last, k end
        end
        if count >= MAX_GATHERED then map[oldestKey] = nil end
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
local miniEv = CreateFrame("Frame")

local function NodeTip(owner, ident, extra)
    local node = NODES[ident]
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(("%s (%d)"):format(CUI.L(node[3]), node[2]), 1, 1, 1)
    local tier = NodeTier(ident)
    if tier then
        local c = TIER_RGB[tier]
        GameTooltip:AddLine(TierText(node[1], node[2], tier), c.r, c.g, c.b)
    end
    if extra then
        local m = CUI.Kit.Palette.muted
        GameTooltip:AddLine(extra, m[1], m[2], m[3])
    end
    GameTooltip:Show()
end

local function NewMiniPin()
    local pin = CreateFrame("Frame", nil, Minimap)
    pin.ring = pin:CreateTexture(nil, "BACKGROUND")
    pin.ring:SetTexture(MEDIA .. "ring")
    pin.ring:SetPoint("CENTER")
    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetPoint("CENTER")
    pin.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    pin:EnableMouse(true)
    pin:SetScript("OnEnter", function(self) NodeTip(self, self.id) end)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return pin
end

-- With Find Herbs / Find Minerals tracking, the icon moves to the ring's
-- corner so the game's own dot shows inside it when the node is up.
local function PaintMiniPin(pin, list, i)
    local ident = list[i * 3 - 2]
    local node = NODES[ident]
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
    pin.icon:SetTexture(C_Spell.GetSpellTexture(ICON_SPELL[node[1]]))
    local c = NodeColor(ident)
    pin.ring:SetVertexColor(c.r, c.g, c.b)
end

local function Track()
    wipe(tracked)
    if not (C_Minimap and C_Minimap.GetNumTrackingTypes) then return end
    for i = 1, C_Minimap.GetNumTrackingTypes() do
        local info = C_Minimap.GetTrackingInfo(i)
        if info and info.active then
            for category, spell in pairs(ICON_SPELL) do
                if info.spellID == spell then tracked[category] = true end
            end
        end
    end
end

local function MiniRefresh()
    local on = Enabled() and Get("minimapIcons") and (SpotWanted("ore") or SpotWanted("herb"))
    if not on or not LoadSpots() then
        if mini then mini:Set(nil) end
        return
    end
    Track()
    mini = mini or module.MinimapLayer({
        max = MINIMAP_MAX,
        new = NewMiniPin,
        paint = PaintMiniPin,
        xy = function(list, i) return list[i * 3 - 1] / SPOT_SCALE, list[i * 3] / SPOT_SCALE end,
    })
    local mapID = C_Map.GetBestMapForUnit("player")
    mini:Set(mapID, spots, mapID and SpotsFor(mapID, spots) or 0)
end
miniEv:SetScript("OnEvent", MiniRefresh)

local function MiniApply()
    miniEv:UnregisterAllEvents()
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
            miniEv:RegisterEvent(evt)
        end
    end
    if module.MinimapLayer and IsLoggedIn() then MiniRefresh() end
end

-------------------------------------------------------------------------------
--  Gathered on the world map
-------------------------------------------------------------------------------

local provider, layer, added, waiter, lastGUID
local mapPins, mapUsed = {}, 0
local lootEv = CreateFrame("Frame")

local function MapClear()
    for i = 1, mapUsed do
        mapPins[i]:Hide()
    end
    mapUsed = 0
end

local function MapAnchor(p)
    local canvas = layer:GetParent()
    local wid, hgt = canvas:GetSize()
    local cs = canvas:GetScale()
    p:SetScale(1 / cs)
    p:ClearAllPoints()
    p:SetPoint("CENTER", canvas, "TOPLEFT", p.x * wid * cs, -p.y * hgt * cs)
end

local function MapPin(i)
    local p = mapPins[i]
    if p then return p end
    p = CreateFrame("Frame", nil, layer)
    p.ring = p:CreateTexture(nil, "BACKGROUND")
    p.ring:SetTexture(MEDIA .. "ring")
    p.ring:SetPoint("TOPLEFT", -4, 4)
    p.ring:SetPoint("BOTTOMRIGHT", 4, -4)
    p.icon = p:CreateTexture(nil, "ARTWORK")
    p.icon:SetAllPoints()
    p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    p:EnableMouse(true)
    p:SetScript("OnEnter", function(self)
        NodeTip(self, self.entry.id, CUI.Lf("Gathered %1$d times.", self.entry.count))
    end)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mapPins[i] = p
    return p
end

local function MapDraw()
    MapClear()
    if not (Enabled() and Get("gatheredPins")) then return end
    local mapID = WorldMapFrame:GetMapID()
    for _, entry in pairs(mapID and Gathered(mapID) or {}) do
        local node = NODES[entry.id]
        if node and Get(node[1]) then
            mapUsed = mapUsed + 1
            local p = MapPin(mapUsed)
            local size = Get("gatheredPinSize")
            p.entry, p.x, p.y = entry, entry.x / SPOT_SCALE, entry.y / SPOT_SCALE
            p:SetSize(size, size)
            p.icon:SetTexture(C_Spell.GetSpellTexture(ICON_SPELL[node[1]]))
            local c = NodeColor(entry.id)
            p.ring:SetVertexColor(c.r, c.g, c.b)
            MapAnchor(p)
            p:Show()
        end
    end
end

local function MapBuild()
    layer = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer.Child)
    layer:SetAllPoints()
    layer:SetFrameLevel(WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_AREA_POI"))
    provider = CreateFromMixins(MapCanvasDataProviderMixin)
    provider.OnMapChanged = MapDraw
    provider.RefreshAllData = MapDraw
    provider.RemoveAllData = MapClear
    provider.OnCanvasScaleChanged = function()
        for i = 1, mapUsed do
            MapAnchor(mapPins[i])
        end
    end
    provider.OnGlobalAlphaChanged = function(self) layer:SetAlpha(self:GetMap():GetGlobalAlpha()) end
end

-- A loot window from a herb or vein (by the loot's source GUID) notes it.
local function OnLoot()
    for slot = 1, GetNumLootItems() do
        local sources = { GetLootSourceInfo(slot) }
        for i = 1, #sources, 2 do
            local guid = sources[i]
            if Plain(guid) and type(guid) == "string" then
                local ident = tonumber(guid:match(GUID_OBJECT))
                local node = ident and NODES[ident]
                if node and (node[1] == "ore" or node[1] == "herb") then
                    if guid ~= lastGUID then
                        lastGUID = guid
                        if Record(ident) and WorldMapFrame and WorldMapFrame:IsShown() then MapDraw() end
                    end
                    return
                end
            end
        end
    end
end
lootEv:SetScript("OnEvent", OnLoot)

local function MapApply()
    local on = Enabled() and Get("gatheredPins")
    if on then
        lootEv:RegisterEvent("LOOT_READY")
    else
        lootEv:UnregisterEvent("LOOT_READY")
    end
    if not on then
        if added then
            WorldMapFrame:RemoveDataProvider(provider)
            added = false
        end
        if layer then MapClear() end
        return
    end
    if not provider then
        if not C_AddOns.IsAddOnLoaded("Blizzard_WorldMap") then
            if not waiter then
                waiter = CreateFrame("Frame")
                waiter:SetScript("OnEvent", function(self, _, name)
                    if name ~= "Blizzard_WorldMap" then return end
                    self:UnregisterEvent("ADDON_LOADED")
                    MapApply()
                end)
            end
            waiter:RegisterEvent("ADDON_LOADED")
            return
        end
        MapBuild()
    end
    if not added then
        WorldMapFrame:AddDataProvider(provider)
        added = true
    end
    if WorldMapFrame:IsShown() then MapDraw() end
end

-------------------------------------------------------------------------------

local function Apply()
    ApplyCVars()
    HighlightApply()
    MiniApply()
    MapApply()
end

CUI._Glimmer = {
    Get = Get,
    Cfg = F.Cfg,
    Apply = Apply,
    Categories = CATEGORIES,
    Read = ReadTarget,
    Record = Record,
    Gathered = Gathered,
    -- The effect frame and its line (tests).
    Fx = function() return fx, line end,
    -- For Zone Info: the herbs and ore that grow in a zone, each once, by
    -- skill: { kind, need, name } (nil while the spots cannot be read yet).
    ZoneNodes = function(mapID)
        if not LoadSpots() then return nil end
        local list, seen = {}, {}
        local all = SPOTS[mapID]
        for i = 1, all and #all or 0, 3 do
            local node = NODES[all[i]]
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
    Skill = Skill,
}

F.Start(Apply)
