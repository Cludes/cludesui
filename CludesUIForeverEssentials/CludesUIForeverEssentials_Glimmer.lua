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
local KIND_ROSTER = { "ore", "herb", "quest", "giver", "chest", "bobber", "corpse" }

local DEFAULT_ASSIGN = {
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
local F = module.Feature("glimmer", DEFAULT_ASSIGN)
local Get, Enabled = F.Get, F.Enabled

local SOFT_UNIT = "softinteract"
local BOBBER_ID = 35591
local OBJECT_ID_KIND = "^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"
local CRAFT_ROW_KIND = { ore = 186, herb = 182 }
local GLYPH_FOR_SPELL = { herb = 2383, ore = 2580 }
local SPOT_UNIT = 1000
local SNAP_YARDS = 15
local COLLECT_LOG_TOP = 400
local MINIMAP_MARKER_TOP = 40
local IMAGE_DIR = "Interface\\AddOns\\CludesUI\\media\\glimmer\\"
local TIER_COLOURS = {
    orange = { r = 1, g = 0.5, b = 0.25 },
    yellow = { r = 1, g = 1, b = 0 },
    green = { r = 0.25, g = 0.75, b = 0.25 },
    grey = { r = 0.5, g = 0.5, b = 0.5 },
    red = { r = 1, g = 0.38, b = 0.38 },
}
local BLOCKED_TONE = { r = 0.62, g = 0.62, b = 0.62 }
local TASK_TONE = { r = 1, g = 0.82, b = 0 }
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
    for title, value in pairs(INTERACT_CVARS) do
        local current = C_CVar.GetCVar(title)
        local desired = value()
        if current ~= nil and current ~= desired then
            if c.held[title] == nil then c.held[title] = current end
            CUI.HoldCVar(title, desired, "CludesUIForeverEssentials")
        end
    end
end

local function LetGo()
    local kept = F.Read().held
    if not kept then return end
    for title, value in pairs(kept) do
        CUI.ReleaseCVar(title, value, "CludesUIForeverEssentials")
    end
    local plate = kept[PLATE_SETTING]
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
local function RevealOnPlate(reveal)
    if reveal == plateShown or InCombatLockdown() then return end
    plateShown = reveal
    local c = F.Cfg()
    c.held = c.held or {}
    if c.held[PLATE_SETTING] == nil then c.held[PLATE_SETTING] = C_CVar.GetCVar(PLATE_SETTING) or "0" end
    CUI.HoldCVar(PLATE_SETTING, reveal and "1" or "0", "CludesUIForeverEssentials")
end

-------------------------------------------------------------------------------
--  What the target is
-------------------------------------------------------------------------------

local CURSOR_IMAGE = { Mine = "ore", GatherHerbs = "herb", QuestTurnIn = "quest", Quest = "quest", QuestRepeatable = "quest" }
local CURSOR_KINDS = { herb = "herb", mine = "ore", quest = "quest", important = "quest", recurring = "quest", wrapper = "quest" }
local cursorImageIds, probe

local function CursorImageIds()
    cursorImageIds = {}
    if not GetFileIDFromPath then return end
    for file, category in pairs(CURSOR_IMAGE) do
        local ident = GetFileIDFromPath("Interface\\Cursor\\" .. file)
        if ident then cursorImageIds[ident] = { category, false } end
        ident = GetFileIDFromPath("Interface\\Cursor\\Unable" .. file)
        if ident then cursorImageIds[ident] = { category, true } end
    end
end

local function KindFromTitle(title)
    if type(title) ~= "string" or not Simplified(title) then return end
    title = title:lower()
    local unable = title:find("unable", 1, true) ~= nil
    for word, category in pairs(CURSOR_KINDS) do
        if title:find(word, 1, true) then return category, unable end
    end
    return nil, unable
end

-- The cursor the game would show over the unit: its category and whether
-- it is the "unable" one.
local function Cursor(unit, deferrable)
    if not SetUnitCursorTexture then return end
    if not cursorImageIds then CursorImageIds() end
    probe = probe or CreateFrame("Frame"):CreateTexture()
    if not SetUnitCursorTexture(probe, unit, nil, deferrable) then return end
    local texture = probe:GetTexture()
    if not Simplified(texture) then return end
    local learned = cursorImageIds[texture]
    if learned then return learned[1], learned[2] end
    return KindFromTitle(texture)
end

local function ObjectIdOf(unit)
    local guid = UnitGUID(unit)
    if not (guid and Simplified(guid)) then return end
    return tonumber(guid:match(OBJECT_ID_KIND))
end

local function TaskLabel(unit)
    local data = C_TooltipInfo and C_TooltipInfo.GetUnit and C_TooltipInfo.GetUnit(unit)
    if not (data and Simplified(data) and data.lines) then return end
    local taskLabel = Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective
    for _, row in ipairs(data.lines) do
        if row.type == taskLabel and Simplified(row.leftText) then return row.leftText end
    end
end

local function CraftOf(catalog, rowId)
    if not catalog then return end
    local _, _, rank, _, _, _, row, modifier = GetProfessionInfo(catalog)
    if row == rowId then return (rank or 0) + (modifier or 0) end
end

local function CraftTier(category)
    local row = CRAFT_ROW_KIND[category]
    if not row then return 0 end
    local first, second = GetProfessions()
    return CraftOf(first, row) or CraftOf(second, row) or 0
end

local function TierOf(craft, need)
    if craft < need then return "red" end
    local over = craft - need
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

local load = {}
local function IsSkinnable(unit)
    if not Get("corpse") then return end
    local dead = UnitIsDead(unit)
    if not (Simplified(dead) and dead) then return end
    local guid = UnitGUID(unit)
    if not (guid and Simplified(guid)) then return end
    local holdsSpoils, lootable = CanLootUnit(guid)
    if not (Simplified(holdsSpoils) and Simplified(lootable) and holdsSpoils and lootable) then return end
    wipe(load)
    load.category, load.unable, load.locked, load.ready = "corpse", false, false, Reach(unit)
    return load
end

local function IsTaskSource(unit)
    local category, unable = Cursor(unit, true)
    if category ~= "quest" then return end
    wipe(load)
    load.category, load.unable = "giver", unable or false
    load.locked, load.ready = load.unable, Reach(unit)
    return load
end

local function LoadSoftAim(unit)
    local object = UnitIsGameObject and UnitIsGameObject(unit)
    if not Simplified(object) then return end
    if not object then return IsSkinnable(unit) or IsTaskSource(unit) end
    wipe(load)
    local ident = ObjectIdOf(unit)
    local node = ident and NODE_INFO[ident]
    local cursorKind, unable = Cursor(unit)
    local category = node and node[1] or (ident == BOBBER_ID and "bobber") or cursorKind
    load.id, load.unable = ident, unable or false
    if category == "ore" or category == "herb" then
        load.skill = CraftTier(category)
        load.need = node and node[2]
        if load.need then load.tier = TierOf(load.skill, load.need) end
        load.locked = load.tier == "red" or load.skill <= 0 or load.unable
    else
        local row = TaskLabel(unit)
        local related = C_QuestLog.UnitIsRelatedToActiveQuest and C_QuestLog.UnitIsRelatedToActiveQuest(unit)
        if row or (Simplified(related) and related) then
            category = "quest"
            load.line = row
        end
        load.locked = load.unable
    end
    if not category then return end
    load.category, load.ready = category, Reach(unit)
    return load
end

local function Tint(category) return { r = Get(category .. "R"), g = Get(category .. "G"), b = Get(category .. "B") } end

-------------------------------------------------------------------------------
--  Effects (five styles, one frame)
-------------------------------------------------------------------------------

local sin, cos, sqrt, random, least, max, pi = math.sin, math.cos, math.sqrt, math.random, math.min, math.max, math.pi
local FULL_HAND = pi * 2
local BASE, DISTANT_ALPHA, BLOCKED_ALPHA, BLOCKED_SPEED = 48, 0.5, 0.55, 0.5
local DIM_SECONDS, BLEND_MODE, FLASH_SECONDS, STEP_LIMIT = 0.3, 0.25, 0.5, 0.1
local SPARKLE_TALLY, PATH_TALLY, PATH_LENGTH, RISE_TALLY = 14, 2, 6, 5
local CORNER_ASSIGN = { { -1, 1, 0, 1, 0, 1 }, { 1, 1, 1, 0, 0, 1 }, { 1, -1, 1, 0, 1, 0 }, { -1, -1, 0, 1, 1, 0 } }

local function TextureFor(fx, file, layer)
    local t = fx:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(IMAGE_DIR .. file)
    t:SetBlendMode("ADD")
    t:Hide()
    return t
end

local function RespawnInfo(sparkleRef, now)
    local angle, reach = random() * FULL_HAND, sqrt(random())
    sparkleRef.x, sparkleRef.y = cos(angle) * reach * 0.9, sin(angle) * reach * 0.7
    sparkleRef.life = 0.6 + 0.8 * random()
    sparkleRef.scale = 0.5 + 0.7 * random()
    sparkleRef.angle = random() * FULL_HAND
    sparkleRef.spin = (random() - 0.5) * 2
    sparkleRef.age = now and 0 or -0.6 * random()
end

local function EaseTo(v, aim, step)
    if v < aim then return least(v + step, aim) end
    return max(v - step, aim)
end

local function Redraw(t, fx, alpha) t:SetVertexColor(fx.r, fx.g, fx.b, max(0, least(1, alpha))) end

local function Position(t, fx, x, y, w, h)
    t:ClearAllPoints()
    t:SetPoint("CENTER", fx, "CENTER", x, y)
    t:SetSize(max(w, 0.01), max(h or w, 0.01))
end

local RENDER_LAYER = {}
function RENDER_LAYER.glow(fx, a, B)
    Position(fx.glow, fx, 0, 0, B * 2.6 * (1 + 0.08 * sin(fx.time * 3)))
    Redraw(fx.glow, fx, a * 0.7)
    Position(fx.core, fx, 0, 0, B * 1.1)
    fx.core:SetVertexColor(1, 1, 1, a * 0.35 * (0.5 + 0.5 * fx.lock))
end
function RENDER_LAYER.sparkles(fx, a, B, step)
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
function RENDER_LAYER.ring(fx, a, B)
    local gy = B * -0.35
    Position(fx.ring, fx, 0, gy, B * 2.6, B * 0.95)
    Redraw(fx.ring, fx, a)
    local rx, ry = B * 1.3, B * 0.475
    for c, tail in ipairs(fx.comets) do
        local head = fx.time * 1.6 + (c - 1) * FULL_HAND / #fx.comets
        for j, t in ipairs(tail) do
            local an, dim = head - (j - 1) * 0.09, 1 - (j - 1) / #tail
            Position(t, fx, cos(an) * rx, gy + sin(an) * ry, B * 0.42 * dim * 1.8)
            Redraw(t, fx, a * dim)
        end
    end
end
function RENDER_LAYER.beam(fx, a, B)
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
function RENDER_LAYER.brackets(fx, a, B)
    local far = 1 - fx.lock
    local h = B * (0.95 + 0.5 * far + far * 0.08 * sin(fx.time * 2.5))
    for i, t in ipairs(fx.brackets) do
        local c = CORNER_ASSIGN[i]
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
    elapsed = least(elapsed, STEP_LIMIT)
    local slow = fx.locked and BLOCKED_SPEED or 1
    fx.time = fx.time + elapsed * slow
    fx.appear = EaseTo(fx.appear, 1, elapsed / DIM_SECONDS)
    fx.lock = EaseTo(fx.lock, fx.ready and 1 or 0, elapsed / BLEND_MODE)
    local a = fx.appear * fx.alpha * (DISTANT_ALPHA + (1 - DISTANT_ALPHA) * fx.lock)
    if fx.locked then a = a * BLOCKED_ALPHA end
    local B = BASE * fx.size
    RENDER_LAYER[fx.style](fx, a, B, elapsed * slow)
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

local function FreshSparkle(parent)
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
    local sparkleTextures, pathTextures = {}, {}
    for i = 1, SPARKLE_TALLY do
        local g = { tex = TextureFor(fx, "flare", "OVERLAY") }
        RespawnInfo(g)
        fx.glints[i], sparkleTextures[i] = g, g.tex
    end
    for c = 1, PATH_TALLY do
        fx.comets[c] = {}
        for j = 1, PATH_LENGTH do
            local t = TextureFor(fx, "glow")
            fx.comets[c][j] = t
            pathTextures[#pathTextures + 1] = t
        end
    end
    for i = 1, RISE_TALLY do
        local t = TextureFor(fx, "flare", "OVERLAY")
        t.lane = i / (RISE_TALLY + 1)
        fx.risers[i] = t
    end
    for i = 1, #CORNER_ASSIGN do
        fx.brackets[i] = TextureFor(fx, "bracket")
    end
    fx.parts = {
        glow = { fx.glow },
        core = { fx.core },
        ring = { fx.ring },
        beam = { fx.beam },
        glints = sparkleTextures,
        comets = pathTextures,
        risers = fx.risers,
        brackets = fx.brackets,
    }
    fx:SetScript("OnUpdate", Advance)
    return fx
end

local function UseSparkle(fx, skin, tint, alpha, size, ready, locked)
    if not SPARKLE_PIECES[skin] then skin = "sparkles" end
    if fx.style ~= skin or not fx.styled then
        fx.style, fx.styled = skin, true
        for _, roster in pairs(fx.parts) do
            for _, t in ipairs(roster) do
                t:Hide()
            end
        end
        for _, key in ipairs(SPARKLE_PIECES[skin]) do
            for _, t in ipairs(fx.parts[key]) do
                t:Show()
            end
        end
    end
    if locked then tint = BLOCKED_TONE end
    fx.r, fx.g, fx.b = tint.r, tint.g, tint.b
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

local PLATE_OFFSET_Y, TILE_OFFSET_Y = -40, -6
local TILE_PIECES = { "HealthBarsContainer", "LevelFrame", "PlayerLevelDiffFrame" }
local fx, row, watch, plate, shown, tileHost
local highlightWindow = CreateFrame("Frame")

local function IsKept()
    if InCombatLockdown() then return true end
    return Get("hideInstance") and IsInInstance() and true or false
end

local function RevealTile()
    if not tileHost then return end
    for _, title in ipairs(TILE_PIECES) do
        if tileHost[title] then tileHost[title]:SetAlpha(1) end
    end
    tileHost = nil
end

-- A unit's plate (a corpse, a quest giver): the game shows it only because
-- the soft target's plate is on, so its health bar and level step aside and
-- just the name stays over the effect (only where the plate is the game's own).
local function ConcealTile(to)
    local unitWindow = to.UnitFrame
    if not unitWindow then return end
    tileHost = unitWindow
    for _, title in ipairs(TILE_PIECES) do
        if unitWindow[title] then unitWindow[title]:SetAlpha(0) end
    end
end

local function HaltSparkle()
    if not plate then return end
    RevealTile()
    fx:Hide()
    fx:ClearAllPoints()
    fx:SetParent(UIParent)
    watch:Hide()
    plate, shown = nil, nil
end

local function BuildSparkle()
    if fx then return end
    fx = FreshSparkle(UIParent)
    fx:Hide()
    row = fx:CreateFontString(nil, "OVERLAY")
    CUI.Kit.Font(row, 12, "essentials", "OUTLINE")
    watch = CreateFrame("Frame")
    watch:Hide()
end

local function TileRow(info)
    if info.category == "quest" then return info.line, TASK_TONE end
    if not info.tier then return end
    return TierLabel(info.category, info.need, info.tier), TIER_COLOURS[info.tier]
end

local function RenderSparkle(info)
    local tint = (info.tier and Get("skillColors")) and TIER_COLOURS[info.tier] or Tint(info.category)
    UseSparkle(fx, Get("style"), tint, Get("brightness"), Get("size"), info.ready, info.locked)
    local label, c = TileRow(info)
    if label and Get("showLine") then
        row:SetText(label)
        row:SetTextColor(c.r, c.g, c.b)
        row:Show()
    else
        row:Hide()
    end
end

local function FixToPlate(to, info)
    fx:SetParent(to)
    local lvl = to:GetFrameLevel()
    if Simplified(lvl) then fx:SetFrameLevel(math.max(lvl - 1, 0)) end
    if fx.SetIgnoreParentAlpha then fx:SetIgnoreParentAlpha(true) end
    fx:ClearAllPoints()
    fx:SetPoint("CENTER", to, "CENTER", 0, PLATE_OFFSET_Y)
    if info.category == "corpse" or info.category == "giver" then ConcealTile(to) end
    row:ClearAllPoints()
    row:SetPoint("TOP", to, "BOTTOM", 0, TILE_OFFSET_Y)
    plate, shown = to, { ready = info.ready }
    for k, v in pairs(info) do
        shown[k] = v
    end
    RenderSparkle(shown)
    BeginSparkle(fx)
    fx:Show()
    watch:Show()
end

local function DesiredNow(category) return category ~= nil and Get(category) and true or false end

local function Assess()
    if not Enabled() then return HaltSparkle() end
    if IsKept() then
        RevealOnPlate(false)
        return HaltSparkle()
    end
    local info = LoadSoftAim(SOFT_UNIT)
    if not (info and DesiredNow(info.category) and not (info.locked and Get("hideLocked"))) then
        RevealOnPlate(not Get("onlyHighlighted"))
        return HaltSparkle()
    end
    RevealOnPlate(true)
    local to = C_NamePlate.GetNamePlateForUnit(SOFT_UNIT)
    if not (to and Simplified(to)) then return HaltSparkle() end
    if to ~= plate then
        HaltSparkle()
        FixToPlate(to, info)
    else
        for k, v in pairs(info) do
            shown[k] = v
        end
        RenderSparkle(shown)
    end
end

-- Walking into reach (or out of it) brightens or dims the effect, held a
-- moment so the edge of the range does not flicker.
local watchedAt, readyAt, desiredAt = 0, nil, nil
local function WatchSoft(_, elapsed)
    watchedAt = watchedAt + elapsed
    if watchedAt < 0.15 then return end
    watchedAt = 0
    if not shown then return end
    local ready = Reach(SOFT_UNIT)
    if ready == shown.ready then
        desiredAt = nil
        return
    end
    local now = GetTime()
    if ready ~= readyAt or not desiredAt then
        readyAt, desiredAt = ready, now
    elseif now - desiredAt >= 0.15 then
        shown.ready, desiredAt = ready, nil
        RenderSparkle(shown)
    end
end

highlightWindow:SetScript("OnEvent", function(_, evt, unit)
    if evt == "PLAYER_REGEN_DISABLED" then
        RevealOnPlate(false)
        HaltSparkle()
    elseif evt == "NAME_PLATE_UNIT_ADDED" then
        local soft = UnitIsUnit(unit, SOFT_UNIT)
        if not plate and not (Simplified(soft) and not soft) then Assess() end
    elseif evt == "NAME_PLATE_UNIT_REMOVED" then
        if plate and C_NamePlate.GetNamePlateForUnit(unit) == plate then HaltSparkle() end
    elseif evt == "PLAYER_SOFT_INTERACT_CHANGED" then
        HaltSparkle()
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

local function UseHighlight()
    highlightWindow:UnregisterAllEvents()
    if not Enabled() then
        if fx then HaltSparkle() end
        return
    end
    BuildSparkle()
    watch:SetScript("OnUpdate", WatchSoft)
    for _, evt in ipairs(HIGHLIGHT_EVENTS) do
        highlightWindow:RegisterEvent(evt)
    end
    HaltSparkle()
    Assess()
end

-------------------------------------------------------------------------------
--  Spots: where herbs and ore grow, and the ones you gathered
-------------------------------------------------------------------------------

local SPOT_TABLE
local function UnpackPlaces()
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

local function RevealSpot(category)
    if not Get(category) then return false end
    if not Get("myProfessions") then return true end
    return CraftTier(category) > 0
end

local function ChartPlaces(chartID, out)
    wipe(out)
    local all = SPOT_TABLE and SPOT_TABLE[chartID]
    if not all then return 0 end
    local want = { ore = RevealSpot("ore"), herb = RevealSpot("herb") }
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

local function NodeCraftTier(ident)
    local node = NODE_INFO[ident]
    if not node then return end
    return TierOf(CraftTier(node[1]), node[2])
end

local function NodeTone(ident)
    local node = NODE_INFO[ident]
    local tier = Get("skillColors") and NodeCraftTier(ident)
    return tier and TIER_COLOURS[tier] or Tint(node[1])
end

local function JotGathered(chartID)
    local all = F.Read().gathered
    return all and all[chartID]
end

local function SnapToGrid(chartID, gatheredLog, ident, x, y)
    local topX, topY, top = x, y, SNAP_YARDS * SNAP_YARDS
    for _, e in pairs(gatheredLog) do
        if e.id == ident then
            local d = (e.x - x) ^ 2 + (e.y - y) ^ 2
            if d <= top then topX, topY, top = e.x, e.y, d end
        end
    end
    if top < SNAP_YARDS * SNAP_YARDS then return topX, topY end
    local all = SPOT_TABLE and SPOT_TABLE[chartID]
    for i = 1, all and #all or 0, 3 do
        if all[i] == ident then
            local d = (all[i + 1] - x) ^ 2 + (all[i + 2] - y) ^ 2
            if d <= top then topX, topY, top = all[i + 1], all[i + 2], d end
        end
    end
    return topX, topY
end

local function Remember(ident)
    local chartID = C_Map.GetBestMapForUnit("player")
    local pos = chartID and C_Map.GetPlayerMapPosition(chartID, "player")
    if not pos then return end
    local px, py = pos:GetXY()
    if not (Simplified(px) and Simplified(py)) then return end
    local c = F.Cfg()
    c.gathered = c.gathered or {}
    local chart = c.gathered[chartID] or {}
    c.gathered[chartID] = chart
    local x, y = SnapToGrid(chartID, chart, ident, math.floor(px * SPOT_UNIT + 0.5), math.floor(py * SPOT_UNIT + 0.5))
    local key = ("%d:%d:%d"):format(ident, x, y)
    local item = chart[key]
    if not item then
        local tally, oldest, oldestId = 0, nil, nil
        for k, e in pairs(chart) do
            tally = tally + 1
            if not oldest or e.last < oldest then oldest, oldestId = e.last, k end
        end
        if tally >= COLLECT_LOG_TOP then chart[oldestId] = nil end
        item = { id = ident, x = x, y = y, count = 0 }
        chart[key] = item
    end
    item.count, item.last = item.count + 1, time()
    return item
end

-------------------------------------------------------------------------------
--  Minimap spots
-------------------------------------------------------------------------------

local mini
local places, tracked = {}, {}
local minimapWindow = CreateFrame("Frame")

local function NodeTooltip(owner, ident, extra)
    local node = NODE_INFO[ident]
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(("%s (%d)"):format(CUI.L(node[3]), node[2]), 1, 1, 1)
    local tier = NodeCraftTier(ident)
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

local function FreshMinimapMarker()
    local marker = CreateFrame("Frame", nil, Minimap)
    marker.ring = marker:CreateTexture(nil, "BACKGROUND")
    marker.ring:SetTexture(IMAGE_DIR .. "ring")
    marker.ring:SetPoint("CENTER")
    marker.icon = marker:CreateTexture(nil, "ARTWORK")
    marker.icon:SetPoint("CENTER")
    marker.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    marker:EnableMouse(true)
    marker:SetScript("OnEnter", function(self) NodeTooltip(self, self.id) end)
    marker:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return marker
end

-- With Find Herbs / Find Minerals tracking, the icon moves to the ring's
-- corner so the game's own dot shows inside it when the node is up.
local function RenderMinimapMarker(marker, roster, i)
    local ident = roster[i * 3 - 2]
    local node = NODE_INFO[ident]
    local size = Get("minimapSize")
    marker.id = ident
    marker:SetSize(size, size)
    marker.ring:SetSize(size * 1.6, size * 1.6)
    marker.icon:ClearAllPoints()
    if tracked[node[1]] then
        marker.icon:SetPoint("CENTER", size * 0.57, -size * 0.57)
        marker.icon:SetSize(size * 0.45, size * 0.45)
    else
        marker.icon:SetPoint("CENTER")
        marker.icon:SetSize(size * 0.7, size * 0.7)
    end
    marker.icon:SetTexture(C_Spell.GetSpellTexture(GLYPH_FOR_SPELL[node[1]]))
    local c = NodeTone(ident)
    marker.ring:SetVertexColor(c.r, c.g, c.b)
end

local function Follow()
    wipe(tracked)
    if not (C_Minimap and C_Minimap.GetNumTrackingTypes) then return end
    for i = 1, C_Minimap.GetNumTrackingTypes() do
        local info = C_Minimap.GetTrackingInfo(i)
        if info and info.active then
            for category, spell in pairs(GLYPH_FOR_SPELL) do
                if info.spellID == spell then tracked[category] = true end
            end
        end
    end
end

local function RenewMinimapMarkers()
    local on = Enabled() and Get("minimapIcons") and (RevealSpot("ore") or RevealSpot("herb"))
    if not on or not UnpackPlaces() then
        if mini then mini:Set(nil) end
        return
    end
    Follow()
    mini = mini or module.MinimapLayer({
        max = MINIMAP_MARKER_TOP,
        new = FreshMinimapMarker,
        paint = RenderMinimapMarker,
        xy = function(roster, i) return roster[i * 3 - 1] / SPOT_UNIT, roster[i * 3] / SPOT_UNIT end,
    })
    local chartID = C_Map.GetBestMapForUnit("player")
    mini:Set(chartID, places, chartID and ChartPlaces(chartID, places) or 0)
end
minimapWindow:SetScript("OnEvent", RenewMinimapMarkers)

local function UseMinimapMarkers()
    minimapWindow:UnregisterAllEvents()
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
            minimapWindow:RegisterEvent(evt)
        end
    end
    if module.MinimapLayer and IsLoggedIn() then RenewMinimapMarkers() end
end

-------------------------------------------------------------------------------
--  Gathered on the world map
-------------------------------------------------------------------------------

local provider, layer, added, waiter, lastSoft
local chartMarkerPool, chartMarkersUsed = {}, 0
local spoilsWindow = CreateFrame("Frame")

local function WipeChartMarkers()
    for i = 1, chartMarkersUsed do
        chartMarkerPool[i]:Hide()
    end
    chartMarkersUsed = 0
end

local function ChartLayer(p)
    local canvas = layer:GetParent()
    local wid, hgt = canvas:GetSize()
    local cs = canvas:GetScale()
    p:SetScale(1 / cs)
    p:ClearAllPoints()
    p:SetPoint("CENTER", canvas, "TOPLEFT", p.x * wid * cs, -p.y * hgt * cs)
end

local function ChartMarkerAt(i)
    local p = chartMarkerPool[i]
    if p then return p end
    p = CreateFrame("Frame", nil, layer)
    p.ring = p:CreateTexture(nil, "BACKGROUND")
    p.ring:SetTexture(IMAGE_DIR .. "ring")
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
    chartMarkerPool[i] = p
    return p
end

local function RenderChartMarkers()
    WipeChartMarkers()
    if not (Enabled() and Get("gatheredPins")) then return end
    local chartID = WorldMapFrame:GetMapID()
    for _, item in pairs(chartID and JotGathered(chartID) or {}) do
        local node = NODE_INFO[item.id]
        if node and Get(node[1]) then
            chartMarkersUsed = chartMarkersUsed + 1
            local p = ChartMarkerAt(chartMarkersUsed)
            local size = Get("gatheredPinSize")
            p.entry, p.x, p.y = item, item.x / SPOT_UNIT, item.y / SPOT_UNIT
            p:SetSize(size, size)
            p.icon:SetTexture(C_Spell.GetSpellTexture(GLYPH_FOR_SPELL[node[1]]))
            local c = NodeTone(item.id)
            p.ring:SetVertexColor(c.r, c.g, c.b)
            ChartLayer(p)
            p:Show()
        end
    end
end

local function BuildChartLayer()
    layer = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer.Child)
    layer:SetAllPoints()
    layer:SetFrameLevel(WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_AREA_POI"))
    provider = CreateFromMixins(MapCanvasDataProviderMixin)
    provider.OnMapChanged = RenderChartMarkers
    provider.RefreshAllData = RenderChartMarkers
    provider.RemoveAllData = WipeChartMarkers
    provider.OnCanvasScaleChanged = function()
        for i = 1, chartMarkersUsed do
            ChartLayer(chartMarkerPool[i])
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
                local ident = tonumber(guid:match(OBJECT_ID_KIND))
                local node = ident and NODE_INFO[ident]
                if node and (node[1] == "ore" or node[1] == "herb") then
                    if guid ~= lastSoft then
                        lastSoft = guid
                        if Remember(ident) and WorldMapFrame and WorldMapFrame:IsShown() then RenderChartMarkers() end
                    end
                    return
                end
            end
        end
    end
end
spoilsWindow:SetScript("OnEvent", OnLooted)

local function UseChartMarkers()
    local on = Enabled() and Get("gatheredPins")
    if on then
        spoilsWindow:RegisterEvent("LOOT_READY")
    else
        spoilsWindow:UnregisterEvent("LOOT_READY")
    end
    if not on then
        if added then
            WorldMapFrame:RemoveDataProvider(provider)
            added = false
        end
        if layer then WipeChartMarkers() end
        return
    end
    if not provider then
        if not C_AddOns.IsAddOnLoaded("Blizzard_WorldMap") then
            if not waiter then
                waiter = CreateFrame("Frame")
                waiter:SetScript("OnEvent", function(self, _, title)
                    if title ~= "Blizzard_WorldMap" then return end
                    self:UnregisterEvent("ADDON_LOADED")
                    UseChartMarkers()
                end)
            end
            waiter:RegisterEvent("ADDON_LOADED")
            return
        end
        BuildChartLayer()
    end
    if not added then
        WorldMapFrame:AddDataProvider(provider)
        added = true
    end
    if WorldMapFrame:IsShown() then RenderChartMarkers() end
end

-------------------------------------------------------------------------------

local function Apply()
    HoldInteractCVars()
    UseHighlight()
    UseMinimapMarkers()
    UseChartMarkers()
end

CUI._Glimmer = {
    Get = Get,
    Cfg = F.Cfg,
    Apply = Apply,
    Categories = KIND_ROSTER,
    Read = LoadSoftAim,
    Record = Remember,
    Gathered = JotGathered,
    -- The effect frame and its line (tests).
    Fx = function() return fx, row end,
    -- For Zone Info: the herbs and ore that grow in a zone, each once, by
    -- skill: { kind, need, name } (nil while the spots cannot be read yet).
    ZoneNodes = function(chartID)
        if not UnpackPlaces() then return nil end
        local roster, spotted = {}, {}
        local all = SPOT_TABLE[chartID]
        for i = 1, all and #all or 0, 3 do
            local node = NODE_INFO[all[i]]
            local key = node and (node[1] .. ":" .. node[3])
            if node and (node[1] == "herb" or node[1] == "ore") and not spotted[key] then
                spotted[key] = true
                roster[#roster + 1] = { kind = node[1], need = node[2], name = node[3] }
            end
        end
        table.sort(roster, function(a, b)
            if a.need ~= b.need then return a.need < b.need end
            return a.name < b.name
        end)
        return roster
    end,
    Skill = CraftTier,
}

F.Start(Apply)
