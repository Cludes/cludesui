if CUI_CLIENT_BLOCKED then
    return
end
local _, mod = ...

-- CUI_DEBUFF_COLORS: declarative aura slots own visibility. Never read aura
-- payloads, inspect secure button visibility, or infer debuffs from casts.
local bundles = {} -- plate -> its tint bundle (reused when its unit changes)
local settings
local job
local pendingRefresh = false
local WHITE = "Interface\\Buttons\\WHITE8x8"
local STYLE = "np:debuffColorPresence"

-- Spell IDs identify DEBUFFS (Rake's damage spell, for example, is 1822).
-- Curated for debuffs players maintain on individual enemies. Names and icons
-- come from the client; verified icon paths cover unavailable spell metadata.
-- A debuff row's spell menu offers only its class's presets, in this order.
mod.DebuffColorPresets = {
    { 703, "Garrote", "Rogue", "Interface\\Icons\\ability_rogue_garrote" },
    { 1943, "Rupture", "Rogue", "Interface\\Icons\\ability_rogue_rupture" },
    { 164812, "Moonfire", "Druid", "Interface\\Icons\\spell_nature_starfall" },
    { 164815, "Sunfire", "Druid", "Interface\\Icons\\ability_mage_firestarter" },
    { 1079, "Rip", "Druid", "Interface\\Icons\\ability_ghoulfrenzy" },
    { 155722, "Rake", "Druid", "Interface\\Icons\\ability_druid_disembowel" },
    { 34914, "Vampiric Touch", "Priest", "Interface\\Icons\\spell_holy_stoicism" },
    { 589, "Shadow Word: Pain", "Priest", "Interface\\Icons\\spell_shadow_shadowwordpain" },
    { 980, "Agony", "Warlock", "Interface\\Icons\\spell_shadow_curseofsargeras" },
    { 1259790, "Unstable Affliction", "Warlock", "Interface\\Icons\\spell_shadow_unstableaffliction_3" },
    { 146739, "Corruption", "Warlock", "Interface\\Icons\\spell_shadow_abominationexplosion" },
    { 445474, "Wither", "Warlock", "Interface\\Icons\\inv_ability_hellcallerwarlock_wither" },
    { 188389, "Flame Shock", "Shaman", "Interface\\Icons\\spell_fire_flameshock" },
}
mod.DebuffColorPresetByID = {}
for _, spell in ipairs(mod.DebuffColorPresets) do
    mod.DebuffColorPresetByID[spell[1]] = spell
end

local function Value(colorKey)
    local p = mod.NP_GetProfile()
    if p and p[colorKey] ~= nil then
        return p[colorKey]
    end
    return mod.defaults[colorKey]
end

-------------------------------------------------------------------------------
-- The debuff lists: one setting per class ("debuffColors" .. class token)
-- holding its single debuffs, then its combos, each list in priority order
-- (the higher entry wins), as one string so a profile copy or a per-spec
-- override carries a class's whole list as one value:
--   "spellID:r,g,b;!spellID:r,g,b/spellID+spellID:r,g,b"
-- A "!" marks a debuff that colors while it is missing (While Missing below).
-- Spell 0 is a debuff not chosen yet; a combo needs two to four spells. The
-- options page edits the lists through this kit; the plates read only the
-- player's own class.
-------------------------------------------------------------------------------
local DC = {
    MAX_SINGLES = 10,
    MAX_MISSING = 5,
    MAX_COMBOS = 5,
    MAX_COMBO_SPELLS = 4,
    SINGLE_COLOR = { r = 1.00, g = 0.43, b = 0.04 },
    COMBO_COLOR = { r = 0.10, g = 0.88, b = 0.32 },
}
mod.DebuffColorKit = DC

function DC.Key(class)
    return "debuffColors" .. class
end

function DC.SpellID(val)
    local ident = tonumber(val)
    if ident and ident > 0 and ident == math.floor(ident) then
        return ident
    end
end

local function ParseColor(s, skinData)
    local red, green, blue = s:match("^([%d%.]+),([%d%.]+),([%d%.]+)$")
    red, green, blue = tonumber(red), tonumber(green), tonumber(blue)
    if not (red and green and blue) then
        return { r = skinData.r, g = skinData.g, b = skinData.b }
    end
    return { r = math.min(red, 1), g = math.min(green, 1), b = math.min(blue, 1) }
end

local function Num(val)
    return (string.format("%.4f", val):gsub("%.?0+$", ""))
end
local function ColorText(c)
    return Num(c.r) .. "," .. Num(c.g) .. "," .. Num(c.b)
end

-- A saved list as fresh tables: singles = { { spell, color, missing } },
-- combos = { { spells = { ids }, color } }.
function DC.Parse(s)
    local singles, comboList = {}, {}
    if type(s) ~= "string" then
        return singles, comboList
    end
    local singlePart, comboPart = s:match("^([^/]*)/?(.*)$")
    for record in singlePart:gmatch("[^;]+") do
        if #singles == DC.MAX_SINGLES then
            break
        end
        local miss, ident, rgb = record:match("^(!?)(%d*):?(.*)$")
        singles[#singles + 1] = {
            spell = DC.SpellID(ident) or 0,
            color = ParseColor(rgb, DC.SINGLE_COLOR),
            missing = miss == "!" or nil,
        }
    end
    for record in comboPart:gmatch("[^;]+") do
        if #comboList == DC.MAX_COMBOS then
            break
        end
        local ids, rgb = record:match("^([%d%+]*):?(.*)$")
        local spellSet = {}
        for ident in ids:gmatch("%d+") do
            ident = DC.SpellID(ident)
            if ident and #spellSet < DC.MAX_COMBO_SPELLS then
                spellSet[#spellSet + 1] = ident
            end
        end
        comboList[#comboList + 1] = { spells = spellSet, color = ParseColor(rgb, DC.COMBO_COLOR) }
    end
    return singles, comboList
end

-- The string to save (nil once both lists are empty).
function DC.Encode(singles, comboList)
    if #singles == 0 and #comboList == 0 then
        return nil
    end
    local s, c = {}, {}
    for index, e in ipairs(singles) do
        s[index] = (e.missing and "!" or "") .. e.spell .. ":" .. ColorText(e.color)
    end
    for index, e in ipairs(comboList) do
        c[index] = table.concat(e.spells, "+") .. ":" .. ColorText(e.color)
    end
    return table.concat(s, ";") .. "/" .. table.concat(c, ";")
end

-- A class's lists; get reads the caller's profile (the plates' by default).
function DC.Read(class, get)
    return DC.Parse((get or Value)(DC.Key(class)))
end

-- What the color goes on: "nameplate" (the health fill, in the bar's texture),
-- "texture" (the health fill, in debuffColorsTexture), "border" or "name". A
-- view over debuffColorsMode, which holds only the last two, and the older
-- debuffColorsBorder (Color Border, else Color Nameplate).
function DC.Mode(get)
    get = get or Value
    local m = get("debuffColorsMode")
    if m == "texture" or m == "name" then
        return m
    end
    return get("debuffColorsBorder") == true and "border" or "nameplate"
end

local function Distinct(spellSet)
    local result, seen = {}, {}
    for _, ident in ipairs(spellSet) do
        if not seen[ident] then
            seen[ident] = true
            result[#result + 1] = ident
        end
    end
    return result
end

-- Extra Border Size (whole pixels), for the borders drawn as plain strips.
local function ExtraBorderPx()
    local val = tonumber(Value("debuffColorsBorderExtra")) or 0
    return math.max(0, math.floor(val + 0.5))
end

-- Color Border: the border a plate shows, as the numbers its own apply draws it
-- with (plate:ApplyBorder, ns.ApplyCustomBorderStyle). kind "strips" = Basic
-- and Custom Solid, four strips inside the bar, Extra Border Size added; kind
-- "slices" = a textured Custom border, the eight pieces its edge art is cut
-- into. nil while the plate draws no CUI border (Border None, a stock style,
-- size 0, an unresolved texture): then there is nothing to color.
local function BorderSpec()
    if mod.NP_Blizz() then
        return nil
    end
    local s
    if mod.IsCustomBorderEnabled() then
        local texture = Value("customBorderTexture")
        local size = Value("customBorderSize") or 0
        if size <= 0 then
            return nil
        end
        local px = CludesUI.BorderPx(Value("customBorderSizePx"), size, texture)
        -- On MEDIUM strata. The border frame sits one level above the bar (one
        -- below it when drawn behind); a textured border draws on that frame,
        -- a Solid one on the pixel border's container one level higher. The
        -- color goes one level above whichever draws: up = levels above the
        -- border frame (MakeBorderInit places that frame's level).
        local behind = Value("customBorderBehind") == true
        if not texture or texture == "" or texture == "solid" then
            s = {
                kind = "strips",
                px = (px or size) + ExtraBorderPx(),
                strata = "MEDIUM",
                behind = behind,
                up = 2,
            }
        else
            local filePath = CludesUI.ResolveBorderTexture(texture)
            if not filePath then
                return nil
            end
            s = {
                kind = "slices",
                path = filePath,
                tex = texture,
                size = size,
                px = px,
                strata = "MEDIUM",
                behind = behind,
                up = 1,
                offX = Value("customBorderOffset"),
                offY = Value("customBorderOffsetY"),
                shX = Value("customBorderShiftX"),
                shY = Value("customBorderShiftY"),
            }
        end
    elseif mod.IsBorderEnabled() then
        -- Basic: the bar's own strips sit one level above the bar; the color
        -- goes above them (up = levels above the bar).
        s = { kind = "strips", px = mod.NP_BorderSize() + ExtraBorderPx(), up = 2 }
    else
        return nil
    end
    -- The pixel grid the copy is drawn on: strips in physical pixels
    -- (PP.perfect), slices in UI units of the exact border size (PP.mult).
    local Pix = CludesUI.PP
    s.key = table.concat({
        s.kind,
        tostring(s.px),
        tostring(s.path),
        tostring(s.tex),
        tostring(s.size),
        tostring(s.offX),
        tostring(s.offY),
        tostring(s.shX),
        tostring(s.shY),
        tostring(s.strata),
        tostring(s.behind),
        s.up,
        s.kind == "strips" and Pix.perfect or Pix.mult,
    }, ",")
    return s
end

local function ReadConfig()
    local _, class = UnitClass("player")
    local singles, comboList = DC.Read(class or "")
    local playerOnly = Value("debuffColorsPlayerOnly") ~= false
    local c = {
        enabled = Value("debuffColorsEnabled") == true,
        filterTokens = playerOnly and { "HARMFUL", "PLAYER" } or { "HARMFUL" },
        singles = {},
        combos = {},
    }
    local mode = DC.Mode()
    local parts = { tostring(c.enabled), tostring(playerOnly), mode }
    -- Color Border draws over the plate's border; Color Nameplate tints the
    -- health fill with the bar's own texture, Texture Nameplate with the one
    -- picked for it (the bar's until then); Color Name draws the name again.
    -- channel: the threat color each one gives way to (see Threat).
    if mode == "border" then
        c.border = BorderSpec()
        c.channel = "border"
        parts[#parts + 1] = c.border and c.border.key or "noborder"
    elseif mode == "name" then
        c.name, c.channel = true, "name"
    else
        local colorKey = Value("healthBarTexture")
        if mode == "texture" then
            colorKey = Value("debuffColorsTexture") or colorKey
        end
        c.texture = CludesUI.ResolveTexturePath(mod.healthBarTextures, colorKey, WHITE)
        c.channel = "health"
        parts[#parts + 1] = tostring(c.texture)
    end
    -- Declared bottom to top (a later-declared slot draws on top): the single
    -- debuffs from the end of the list up, then the combos the same way, so a
    -- combo always wins over a single debuff. Missing debuffs draw over both, on
    -- OVERLAY -4 down to -8 by list order (under the bar's shade, hash line,
    -- border and target/focus/hover stripes): one sublevel each, so at most
    -- MAX_MISSING. A spell listed again lower down in the same state can never
    -- show beneath itself, so only its highest entry gets a slot.
    local ranked, seen, missing = {}, {}, 0
    for _, e in ipairs(singles) do
        local colorKey = (e.missing and "!" or "") .. e.spell
        if e.spell > 0 and not seen[colorKey] and not (e.missing and missing == DC.MAX_MISSING) then
            seen[colorKey] = true
            ranked[#ranked + 1] = e
            if e.missing then
                missing = missing + 1
                e.sublevel = -3 - missing
            end
        end
    end
    for index = #ranked, 1, -1 do
        local e = ranked[index]
        c.singles[#c.singles + 1] = {
            spell = e.spell,
            color = e.color,
            sublevel = e.sublevel or (index == 1 and 5) or 4,
            missing = e.missing,
        }
        parts[#parts + 1] = (e.missing and "m" or "s") .. e.spell .. ":" .. ColorText(e.color)
        if e.missing then
            c.anyMissing = true
        end
    end
    for index = #comboList, 1, -1 do
        local spellSet = Distinct(comboList[index].spells)
        if #spellSet >= 2 then
            c.combos[#c.combos + 1] = { spells = spellSet, color = comboList[index].color }
            parts[#parts + 1] = "c" .. table.concat(spellSet, "+") .. ":" .. ColorText(comboList[index].color)
        end
    end
    -- Color Border on a plate with no border has nothing to show.
    c.any = (#c.singles > 0 or #c.combos > 0) and (c.border ~= nil or mode ~= "border")
    c.fingerprint = table.concat(parts, "|")
    return c
end

-- Neighbouring combos (in declaration order) that have a debuff in common
-- share their first slot. A combo shows only while all its debuffs are up, so
-- the debuff its chain starts with never changes when it shows, and the
-- shared slot nests the rest of each combo in the same bottom-to-top order,
-- so nothing draws in a different order. Each sharer saves a root slot and,
-- on every mob carrying the shared debuff, a live nested container.
local function GroupComboRuns(comboList)
    local runs, index = {}, 1
    while index <= #comboList do
        local common = {}
        for _, ident in ipairs(comboList[index].spells) do
            common[ident] = true
        end
        local jdx = index
        while jdx < #comboList do
            local both, any = {}, false
            for _, ident in ipairs(comboList[jdx + 1].spells) do
                if common[ident] then
                    both[ident], any = true, true
                end
            end
            if not any then
                break
            end
            common, jdx = both, jdx + 1
        end
        -- The run's first combo keeps its own spell order where it can, so a
        -- combo with no neighbour to share with builds exactly as saved.
        local first
        for _, ident in ipairs(comboList[index].spells) do
            if common[ident] then
                first = ident
                break
            end
        end
        local run = {}
        for k = index, jdx do
            local spellSet = { first }
            for _, ident in ipairs(comboList[k].spells) do
                if ident ~= first then
                    spellSet[#spellSet + 1] = ident
                end
            end
            run[#run + 1] = { spells = spellSet, color = comboList[k].color }
        end
        runs[#runs + 1] = run
        index = jdx + 1
    end
    return runs
end

-------------------------------------------------------------------------------
-- While Missing: a slot only shows a debuff that is up, so a missing debuff
-- reads a hidden one-aura group (its sensor). The engine lays the group's
-- container out at 1x1 while the debuff is absent and SPAN wide while it is up
-- (AnchorUtil.ApplyFlowLayout); a mask on the container's right edge covers
-- the bar only in the first case, and the color draws through it. Groups can
-- never be removed, so a plate keeps its sensors and re-points them.
-------------------------------------------------------------------------------
local SENSOR_KEY = "CUI_DEBUFF_MISSING"
local REACH = 96 -- past each bar edge, for border art
-- The mask's size and the sensor's width while up: past the widest bar (the
-- Health Bar Width slider's max, 250) plus twice REACH. An 8px texture
-- stretched this far fades over its outer 32px, so border art up to 64px past
-- the bar draws at full strength.
local SPAN = 512
local kits = {} -- plate -> { gate, hider, host, sensors, looks, used, unit, open }
local engagers = {} -- you, your group and the pets out
local engagersStale = true -- a roster or pet change: the next read rebuilds the list
local groupTokens -- the raid and party tokens and their pets', built once
local resync -- the roster re-check's one-shot frame (RequestResync)

local function GroupTokens()
    if not groupTokens then
        groupTokens = { raid = {}, raidpet = {}, party = {}, partypet = {} }
        for index = 1, 40 do
            groupTokens.raid[index], groupTokens.raidpet[index] = "raid" .. index, "raidpet" .. index
        end
        for index = 1, 4 do
            groupTokens.party[index], groupTokens.partypet[index] = "party" .. index, "partypet" .. index
        end
    end
    return groupTokens
end

-- Whether an engager is on the mob's threat list (a mob fighting only
-- strangers is not). Only the type tag is read: the value can be secret.
local function Engaged(unitToken)
    if engagersStale then
        engagersStale = false
        local num = 1
        engagers[1] = "player"
        if UnitExists("pet") then
            num = 2
            engagers[2] = "pet"
        end
        local tokens, raid = GroupTokens(), IsInRaid()
        local who = raid and tokens.raid or tokens.party
        local pets = raid and tokens.raidpet or tokens.partypet
        for index = 1, math.min(GetNumGroupMembers() - (raid and 0 or 1), #who) do
            if not UnitIsUnit(who[index], "player") then
                num = num + 1
                engagers[num] = who[index]
                if UnitExists(pets[index]) then
                    num = num + 1
                    engagers[num] = pets[index]
                end
            end
        end
        for index = #engagers, num + 1, -1 do
            engagers[index] = nil
        end
    end
    for index = 1, #engagers do
        if type(UnitThreatSituation(engagers[index], unitToken)) ~= "nil" then
            return true
        end
    end
    return false
end

-- Shown on an engaged enemy: an assistable unit's debuffs cannot be spell-filtered.
-- nameGated: Color Name's Missing rows (see NameKit).
local function SyncGate(colorKit)
    local open = not UnitCanAssist("player", colorKit.unit, true, true) and Engaged(colorKit.unit)
    if open ~= colorKit.open then
        colorKit.open = open
        colorKit.gate:SetShown(open)
        if colorKit.nameGated then
            colorKit.nameGated:SetShown(open)
        end
    end
end

local function RunResync(self)
    self:Hide()
    self:SetScript("OnUpdate", nil)
    for _, colorKit in pairs(kits) do
        if colorKit.unit then
            SyncGate(colorKit)
        end
    end
end

-- Roster and pet changes come in bursts: the engager list goes stale at once
-- (a gate event in between reads it fresh), and the bound plates are checked
-- again once, on the next frame.
local function RequestResync()
    engagersStale = true
    if not resync then
        resync = CreateFrame("Frame")
        resync:Hide()
    end
    resync:SetScript("OnUpdate", RunResync)
    resync:Show()
end

local function Kit(backing)
    local colorKit = kits[backing]
    if colorKit then
        return colorKit
    end
    -- Only aspect-bearing objects may anchor to a container that holds a group,
    -- and the aspect is inherited at creation: the masks are born in the gate,
    -- and so is the host the Missing rows draw on (DressLook).
    local gate = CreateFrame("Frame", nil, backing.health, "DisableUntrustedLayoutScriptsTemplate")
    gate:SetAllPoints(backing.health)
    gate:Hide()
    local hider = CreateFrame("Frame", nil, backing.health)
    hider:SetAllPoints(backing.health)
    hider:SetAlpha(0)
    hider:Hide()
    local owner = CreateFrame("Frame", nil, gate)
    owner:SetAllPoints(gate)
    colorKit = { gate = gate, hider = hider, host = owner, sensors = {}, looks = {}, used = 0 }
    gate:SetScript("OnEvent", function()
        SyncGate(colorKit)
    end)
    kits[backing] = colorKit
    return colorKit
end

-- Sensor n, pointed at spell. Its mask takes two anchors and a width: a single
-- point and a size draws displaced inside the plate (see PlaceArrow).
local function PointSensor(colorKit, num, spell)
    local AK = CludesUI.AuraKit
    local filter, ids = AK.Filter(unpack(settings.filterTokens)), { includeSpellIDs = { [spell] = true } }
    local s = colorKit.sensors[num]
    if not s then
        local c = AK.CreateContainerShell(
            colorKit.hider,
            { point = { "TOPLEFT", colorKit.hider, "TOPLEFT", -(REACH + 1), REACH } }
        )
        AK.AddGroupToContainer(c, {
            key = SENSOR_KEY,
            filter = settings.filterTokens,
            maxFrameCount = 1,
            style = STYLE,
            candidateFilters = ids,
            layout = { elementWidth = SPAN, elementHeight = 1 },
            extraInit = function(btnFrame)
                btnFrame:EnableMouse(false)
            end,
        })
        local maskTex = colorKit.gate:CreateMaskTexture()
        maskTex:SetTexture(WHITE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        maskTex:SetPoint("TOPLEFT", c, "TOPRIGHT", 0, 0)
        maskTex:SetPoint("BOTTOMLEFT", c, "BOTTOMRIGHT", 0, 1 - SPAN)
        maskTex:SetWidth(SPAN)
        s = { container = c, mask = maskTex, n = num }
        colorKit.sensors[num] = s
    elseif s.spell ~= spell or s.filter ~= filter then
        s.container:SetAuraGroupFilterString(SENSOR_KEY, filter)
        s.container:SetAuraGroupCandidateFilters(SENSOR_KEY, ids)
    end
    s.spell, s.filter = spell, filter
    AK.SetGroupCap(s.container, SENSOR_KEY, 1)
    return s
end

-- Sensors the bundle did not use are switched off (no UNIT_AURA work).
local function ParkSensors(colorKit)
    for num = colorKit.used + 1, #colorKit.sensors do
        CludesUI.AuraKit.SetGroupCap(colorKit.sensors[num].container, SENSOR_KEY, 0)
    end
end

-- The gate's events only while a Missing row reads it (Color Name binds a kit
-- for its sensors alone).
local function BindKit(colorKit, unitToken)
    for num = 1, colorKit.used do
        local s = colorKit.sensors[num]
        if s.unit ~= unitToken then
            s.unit = unitToken
            s.container:SetUnit(unitToken)
        end
    end
    colorKit.hider:Show()
    colorKit.unit, colorKit.open = unitToken, nil
    if settings.anyMissing then
        colorKit.gate:RegisterUnitEvent("UNIT_FLAGS", unitToken)
        colorKit.gate:RegisterUnitEvent("UNIT_THREAT_LIST_UPDATE", unitToken)
        SyncGate(colorKit)
    end
end

local function ParkKit(colorKit)
    colorKit.unit, colorKit.open = nil, nil
    colorKit.gate:UnregisterAllEvents()
    colorKit.gate:Hide()
    colorKit.hider:Hide()
    if colorKit.nameGated then
        colorKit.nameGated:Hide()
    end
end

-- A bundle a settings change replaces can never be freed (frames are permanent);
-- releasing its containers keeps their engine slots out of AuraKit's restyle
-- registry. Refresh runs this out of combat only.
local function ReleaseBundle(b)
    if b.holder then
        b.holder:Hide()
    end
    for _, boxHolder in ipairs(b.containers) do
        boxHolder:SetEnabled(false)
        CludesUI.AuraKit.ReleaseContainer(boxHolder)
    end
    if b.nameKit then
        b.nameKit.attached = nil
        b.nameKit.root:Hide()
    end
    if b.kit then
        ParkKit(b.kit)
    end
end

-- Containers are born enabled on unit "none" and stay enabled: the holder's
-- visibility gates them (a hidden container drops its aura events, a shown
-- one re-reads its unit in full). A new token rebinds every container,
-- nested ones included; the same token needs only the show.
local function BindBundle(b, unitToken)
    if b.unit ~= unitToken then
        b.unit = unitToken
        -- Binding a slot may initialize its nested container; re-read the count.
        local index = 1
        while index <= #b.containers do
            b.containers[index]:SetUnit(unitToken)
            index = index + 1
        end
    end
    b.holder:Show()
end

local function CreateTintContainer(b, hostFrame)
    local c = CludesUI.AuraKit.CreateContainerShell(hostFrame, {})
    c:SetAllPoints(b.holder)
    c:SetFrameLevel(b.level)
    b.containers[#b.containers + 1] = c
    return c
end

-- The health fill's tint: the bar's own texture in the color, over the fill.
local function PaintTint(tintTex, b, rgb)
    tintTex:SetTexture(b.config.texture)
    tintTex:SetVertexColor(rgb.r, rgb.g, rgb.b, 1)
    tintTex:ClearAllPoints()
    tintTex:SetPoint("TOPLEFT", b.fill, "TOPLEFT", 0, 0)
    tintTex:SetPoint("BOTTOMRIGHT", b.fill, "BOTTOMRIGHT", 0, 0)
end

local function MakeTintInit(b, rgb, subLayer)
    local initialized = setmetatable({}, { __mode = "k" })
    return function(btnFrame)
        if initialized[btnFrame] then
            return
        end
        initialized[btnFrame] = true
        -- Only creation-window decoration. Once owned by the aura engine, these
        -- regions may become forbidden; never read or repaint them on rebind.
        btnFrame:SetFrameLevel(b.level)
        btnFrame:EnableMouse(false)
        local tintTex = btnFrame:CreateTexture(nil, "ARTWORK", nil, subLayer)
        PaintTint(tintTex, b, rgb)
        if b.mask then
            tintTex:AddMaskTexture(b.mask)
        end
    end
end

-- Color Border: the plate's border drawn again in the debuff color, just above
-- it (b.config.border, see BorderSpec), so the border reads as recolored while
-- its slot shows. Strips keep whole physical pixels in scale-1 space as the
-- plate scales, like the border's own (the PP scale guard); slices sit on the
-- textured border's own geometry.
-- The copies rank like the tints (a combo over the top single over the rest)
-- without moving past anything else. On a custom border's MEDIUM strata a copy
-- stays one level above the border and its sublevel ranks it (the frames that
-- share that level draw ARTWORK). A Basic copy shares the flattened plate with
-- the border's OVERLAY 7 strips, under which a lower sublevel sinks, so it keeps
-- OVERLAY 7 and ranks by frame level (no other plate frame uses those levels).

-- A copy's frame level: rank levels over the plate border it recolors (a custom
-- border's frame level as ns.ApplyCustomBorderStyle sets it; Basic counts from
-- the bar).
local function CopyLevel(b, specInfo, rank)
    local base = b.level
    if specInfo.behind ~= nil then
        base = specInfo.behind and math.max(1, b.level - 1) or (b.level + 1)
    end
    return base + specInfo.up + rank
end

-- A copy's frame and pieces, not yet colored or placed: four strips, or one
-- texture per edge-art slice (the shared cut table's keys). sensorMask: a
-- Missing row's; the pieces draw through a copy of it on their own frame (it
-- may draw on another strata).
local function NewBorderCopy(hostFrame, specInfo, sensorMask)
    local frame = CreateFrame("Frame", nil, hostFrame)
    frame:EnableMouse(false)
    if specInfo.strata then
        frame:SetFrameStrata(specInfo.strata)
    end
    local maskTex
    if sensorMask then
        maskTex = frame:CreateMaskTexture()
        maskTex:SetTexture(WHITE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        maskTex:SetAllPoints(sensorMask)
    end
    local pieces = {}
    if specInfo.kind == "strips" then
        frame:SetIgnoreParentScale(true)
        frame:SetScale(1)
        for index = 1, 4 do
            local texture = frame:CreateTexture(nil, "OVERLAY")
            if texture.SetSnapToPixelGrid then
                texture:SetSnapToPixelGrid(false)
                texture:SetTexelSnappingBias(0)
            end
            pieces[index] = texture
        end
    else
        for colorKey, coords in pairs(CludesUI.SECRET_BORDER_UV) do
            local texture = frame:CreateTexture(nil, "OVERLAY")
            texture:SetTexCoord(unpack(coords))
            pieces[colorKey] = texture
        end
    end
    if maskTex then
        for _, texture in pairs(pieces) do
            texture:AddMaskTexture(maskTex)
        end
    end
    return frame, pieces
end

local function LayStrip(texture, frame, p1, y1, p2, y2, width, height)
    texture:SetPoint(p1, frame, p1, 0, y1)
    texture:SetPoint(p2, frame, p2, 0, y2)
    if width then
        texture:SetWidth(width)
    else
        texture:SetHeight(height)
    end
end

-- Colors a copy and lays it over owner (the bar's rect), on OVERLAY sublevel.
local function DressBorderCopy(frame, pieces, specInfo, ownerFrame, rgb, subLayer)
    frame:ClearAllPoints()
    frame:SetAllPoints(ownerFrame)
    for _, texture in pairs(pieces) do
        texture:SetDrawLayer("OVERLAY", subLayer)
        texture:ClearAllPoints()
    end
    if specInfo.kind == "strips" then
        local success, es = pcall(frame.GetEffectiveScale, frame)
        if not (success and es and es > 0) then
            es = 1
        end
        local one = CludesUI.PP.perfect / es
        local t = math.max(one, math.floor(specInfo.px + 0.5) * one)
        for _, texture in ipairs(pieces) do
            texture:SetColorTexture(rgb.r, rgb.g, rgb.b, 1)
        end
        LayStrip(pieces[1], frame, "TOPLEFT", 0, "TOPRIGHT", 0, nil, t)
        LayStrip(pieces[2], frame, "BOTTOMLEFT", 0, "BOTTOMRIGHT", 0, nil, t)
        LayStrip(pieces[3], frame, "TOPLEFT", -t, "BOTTOMLEFT", t, t)
        LayStrip(pieces[4], frame, "TOPRIGHT", -t, "BOTTOMRIGHT", t, t)
    else
        for _, texture in pairs(pieces) do
            texture:SetTexture(specInfo.path, true, true)
            texture:SetVertexColor(rgb.r, rgb.g, rgb.b, 1)
        end
        local edge, aL, aT, aR, aB = CludesUI.SecretBorderGeometry(
            frame,
            specInfo.size,
            specInfo.tex,
            specInfo.offX,
            specInfo.offY,
            specInfo.shX,
            specInfo.shY,
            "nameplates",
            specInfo.size,
            nil,
            specInfo.px
        )
        CludesUI.LayoutSecretBorderEdges(pieces, frame, edge, aL, aT, aR, aB)
    end
end

-- A slot's copy, built in the creation window only.
local function MakeBorderInit(b, rgb, subLayer)
    local initialized = setmetatable({}, { __mode = "k" })
    local rank = 0
    if not b.config.border.strata then
        rank = (subLayer == 7 and 2) or (subLayer == 5 and 1) or 0
        subLayer = 7
    end
    return function(btnFrame)
        if initialized[btnFrame] then
            return
        end
        initialized[btnFrame] = true
        btnFrame:SetFrameLevel(b.level)
        btnFrame:EnableMouse(false)
        local specInfo = b.config.border
        local frame, pieces = NewBorderCopy(btnFrame, specInfo)
        frame:SetFrameLevel(CopyLevel(b, specInfo, rank))
        DressBorderCopy(frame, pieces, specInfo, b.holder, rgb, subLayer)
    end
end

-- What a slot shows while its debuffs are up: the health fill's tint (Color
-- Nameplate) or the border in the color (Color Border).
local function ColorInit(b, rgb, subLayer)
    if b.config.border then
        return MakeBorderInit(b, rgb, subLayer)
    end
    return MakeTintInit(b, rgb, subLayer)
end

-- Missing row n draws on the kit's host through sensor n's mask: a tint on
-- OVERLAY at the bar's level (one higher draws over the border), or a copy
-- ranked over every other copy by n. These frames are ours, unlike the slots'
-- engine buttons, so each is built once (a copy once per border style) and
-- dressed again on every rebuild.
local function DressLook(b, sensor, rgb, subLayer)
    local colorKit, num = b.kit, sensor.n
    local look = colorKit.looks[num]
    if not look then
        look = { copies = {} }
        colorKit.looks[num] = look
    end
    local specInfo = b.config.border
    if not specInfo then
        local tintTex = look.tint
        if not tintTex then
            tintTex = colorKit.host:CreateTexture(nil, "OVERLAY")
            if b.mask then
                tintTex:AddMaskTexture(b.mask)
            end
            tintTex:AddMaskTexture(sensor.mask)
            look.tint = tintTex
        end
        tintTex:SetDrawLayer("OVERLAY", subLayer)
        PaintTint(tintTex, b, rgb)
        tintTex:Show()
        return
    end
    local rank = 0
    if not specInfo.strata then
        rank, subLayer = 2, 7
    end
    local style = specInfo.kind .. (specInfo.strata or "")
    local copy = look.copies[style]
    if not copy then
        local frame, pieces = NewBorderCopy(colorKit.host, specInfo, sensor.mask)
        copy = { frame = frame, pieces = pieces }
        look.copies[style] = copy
    end
    copy.frame:SetFrameLevel(CopyLevel(b, specInfo, rank) + num)
    DressBorderCopy(copy.frame, copy.pieces, specInfo, colorKit.host, rgb, subLayer)
    copy.frame:Show()
end

local function HideLooks(colorKit)
    for _, look in ipairs(colorKit.looks) do
        if look.tint then
            look.tint:Hide()
        end
        for _, copy in pairs(look.copies) do
            copy.frame:Hide()
        end
    end
end

local function AddTintSlot(b, boxHolder, colorKey, spell, initialize)
    CludesUI.AuraKit.AddSlotToContainer(boxHolder, {
        key = colorKey,
        filter = b.config.filterTokens,
        style = STYLE,
        candidateFilters = { includeSpellIDs = { [spell] = true } },
        extraInit = initialize,
    })
end

-- Init for a slot whose engine button hosts the next step of a combo: a
-- container nested in the button, filled by declare and bound to the unit.
local function MakeNestInit(b, declare)
    local initialized = setmetatable({}, { __mode = "k" })
    return function(btnFrame)
        if initialized[btnFrame] then
            return
        end
        initialized[btnFrame] = true
        btnFrame:SetFrameLevel(b.level)
        btnFrame:EnableMouse(false)
        local nested = CreateTintContainer(b, btnFrame)
        declare(nested)
        if b.unit then
            nested:SetUnit(b.unit)
        end
    end
end

-- A combo nests one slot per spell, each inside the previous spell's engine
-- button: the tint in the innermost slot renders only while EVERY engine
-- button above it is shown.
local function AddComboSlot(b, boxHolder, colorKey, combo, depth)
    local spell = combo.spells[depth]
    if depth == #combo.spells then
        AddTintSlot(b, boxHolder, colorKey .. "_" .. depth, spell, ColorInit(b, combo.color, 7))
        return
    end
    AddTintSlot(
        b,
        boxHolder,
        colorKey .. "_" .. depth,
        spell,
        MakeNestInit(b, function(nested)
            AddComboSlot(b, nested, colorKey, combo, depth + 1)
        end)
    )
end

-- A run's combos share their first slot; its nested container holds the rest
-- of each combo, declared bottom to top like the runs themselves.
local function AddComboRun(b, boxHolder, colorKey, run)
    AddTintSlot(
        b,
        boxHolder,
        colorKey,
        run[1].spells[1],
        MakeNestInit(b, function(nested)
            for index, combo in ipairs(run) do
                AddComboSlot(b, nested, colorKey .. "_" .. index, combo, 2)
            end
        end)
    )
end

-------------------------------------------------------------------------------
-- Color Name: the plate's name drawn again in the color, over the name. Font
-- strings take no masks, so each copy sits inside clip frames hung on the
-- While Missing sensors (one per debuff spell): a clip covers the name while
-- its sensor's container is SPAN wide (the debuff is up) or, for a Missing
-- row, while it is a single pixel. A combo nests one clip per debuff, so its
-- copy shows only while every one is up. These frames are ours: a plate keeps
-- them across rebuilds and re-points them, and the copies follow the name's
-- text, font and placement through ns.DebuffColors_NameChanged.
-------------------------------------------------------------------------------
local CLIP_REACH = 300 -- above and below a sensor (REACH over the bar): past any name slot
local CHAIN_STEP = 5 -- frame levels per row (a combo nests up to four clips)
local nameKits = {} -- plate -> { root, gated, chains, used, attached }

-- root rides the name's host (MirrorName); gated holds the Missing rows and is
-- shown with the kit's gate. Born with the aspect: only such frames may anchor
-- to a container that holds a group, and their clips inherit it.
local function NameKit(backing, colorKit)
    local kitKey = nameKits[backing]
    if not kitKey then
        local root = CreateFrame("Frame", nil, backing, "DisableUntrustedLayoutScriptsTemplate")
        root:SetAllPoints(backing.health)
        root:Hide()
        local gated = CreateFrame("Frame", nil, root)
        gated:SetAllPoints(root)
        kitKey = { root = root, gated = gated, chains = {}, used = 0 }
        nameKits[backing] = kitKey
    end
    colorKit.nameGated = kitKey.gated
    kitKey.gated:SetShown(colorKit.open == true)
    return kitKey
end

-- Row i's chain: depth clips, each inside the last, the copy in the innermost.
-- Pooled by index; a row that needs more clips adds them.
local function Chain(kitKey, index, depth, hostFrame)
    local channel = kitKey.chains[index]
    if not channel then
        channel = { clips = {} }
        kitKey.chains[index] = channel
    end
    local clips = channel.clips
    for skinData = 1, depth do
        local wanted = (skinData == 1) and hostFrame or clips[skinData - 1]
        local clipFrame = clips[skinData]
        if not clipFrame then
            clipFrame = CreateFrame("Frame", nil, wanted)
            clipFrame:SetClipsChildren(true)
            clips[skinData] = clipFrame
        elseif clipFrame:GetParent() ~= wanted then
            clipFrame:SetParent(wanted)
        end
        clipFrame:Show()
    end
    for skinData = depth + 1, #clips do
        clips[skinData]:Hide()
    end
    channel.depth = depth
    local inner = clips[depth]
    if not channel.copy then
        channel.copy = inner:CreateFontString(nil, "OVERLAY")
    elseif channel.copy:GetParent() ~= inner then
        channel.copy:SetParent(inner)
    end
    return channel
end

-- A clip open while its debuff is up (the sensor's container SPAN wide), or
-- for a Missing row while it is absent (a single pixel; the mask's placement).
local function AnchorClip(clipFrame, sensor, missing)
    local c = sensor.container
    clipFrame:ClearAllPoints()
    if missing then
        clipFrame:SetPoint("TOPLEFT", c, "TOPRIGHT", 0, CLIP_REACH)
        clipFrame:SetPoint("BOTTOMLEFT", c, "BOTTOMRIGHT", 0, -CLIP_REACH)
        clipFrame:SetWidth(SPAN)
    else
        clipFrame:SetPoint("TOPLEFT", c, "TOPLEFT", 0, CLIP_REACH)
        clipFrame:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, -CLIP_REACH)
    end
end

-- A later row draws over an earlier one, every row over the name itself. Each
-- frame takes the root's strata itself, parents first: on the flattened plate a
-- frame that only inherits it renders in the plate's own batch, under the name,
-- and a parent's strata change resets its children's strata and levels.
local function LevelChains(kitKey)
    local strata, base = kitKey.root:GetFrameStrata(), kitKey.root:GetFrameLevel()
    kitKey.gated:SetFrameStrata(strata)
    kitKey.gated:SetFrameLevel(base)
    for index = 1, kitKey.used do
        local channel = kitKey.chains[index]
        for skinData = 1, channel.depth do
            local clipFrame = channel.clips[skinData]
            clipFrame:SetFrameStrata(strata)
            clipFrame:SetFrameLevel(base + (index - 1) * CHAIN_STEP + skinData)
        end
    end
end

-- The copies follow the name: its host (and so its strata), its shown state,
-- font, shadow, justification, wrapping and text. The text may be secret: it
-- only passes from one font string to the others. shownOnly: just the shown
-- state (the name hides while casting, a hot path). The name is a font family
-- (the module's SetFSFont), so each copy takes that same family object, never a
-- plain SetFont (it would pin the copy's face), and a Cyrillic, Korean or
-- Chinese name draws there too. The family object is read rather than the name's
-- GetFont: the member that draws a name is chosen by its text, which may be
-- secret, and the object names the family exactly. A client without font
-- families gives the name a plain font, and the copies take it the same way.
local function MirrorName(backing, shownOnly)
    local b = bundles[backing]
    local kitKey = b and b.nameKit
    if not kitKey then
        return
    end
    local name, root = backing.name, kitKey.root
    root:SetShown(kitKey.attached == true and name:IsShown())
    if shownOnly then
        return
    end
    -- The host's own strata change (SlotTextHost) reaches its children, so the
    -- strata and levels are set again on every pass.
    local owner = name:GetParent()
    if root:GetParent() ~= owner then
        root:SetParent(owner)
    end
    root:SetFrameStrata(owner:GetFrameStrata())
    root:SetFrameLevel(owner:GetFrameLevel() + 1)
    LevelChains(kitKey)
    local fam = name:GetFontObject()
    if not (fam and CludesUI._fontFamilySet[fam]) then
        fam = nil
    end
    local font, size, flags
    if not fam then
        font, size, flags = name:GetFont()
    end
    local sr, sg, scrollBar, sa = name:GetShadowColor()
    local sx, sy = name:GetShadowOffset()
    local jh, jv = name:GetJustifyH(), name:GetJustifyV()
    local wrap, nsWrap, lines = name:CanWordWrap(), name:CanNonSpaceWrap(), name:GetMaxLines()
    local textValue = name:GetText()
    for index = 1, kitKey.used do
        local fontStr = kitKey.chains[index].copy
        if fam then
            if fontStr:GetFontObject() ~= fam then
                fontStr:SetFontObject(fam)
            end
        elseif font then
            fontStr:SetFont(font, size, flags or "")
        end
        fontStr:SetShadowColor(sr, sg, scrollBar, sa)
        fontStr:SetShadowOffset(sx, sy)
        fontStr:SetJustifyH(jh)
        fontStr:SetJustifyV(jv)
        fontStr:SetWordWrap(wrap)
        fontStr:SetNonSpaceWrap(nsWrap)
        fontStr:SetMaxLines(lines)
        fontStr:SetText(textValue)
    end
end

-- The rows bottom to top, as the tints rank: the single debuffs, then the
-- combos, then the Missing ones by their sublevel (the first listed on top).
local function NameEntries(c)
    local result, missing = {}, {}
    for _, e in ipairs(c.singles) do
        if e.missing then
            missing[#missing + 1] = e
        else
            result[#result + 1] = { spells = { e.spell }, color = e.color }
        end
    end
    for _, combo in ipairs(c.combos) do
        result[#result + 1] = { spells = combo.spells, color = combo.color }
    end
    table.sort(missing, function(posX, posY)
        return posX.sublevel < posY.sublevel
    end)
    for _, e in ipairs(missing) do
        result[#result + 1] = { spells = { e.spell }, color = e.color, missing = true }
    end
    return result
end

-- One sensor per debuff spell, shared by every row that names it.
local function CreateNameBundle(backing)
    local colorKit = Kit(backing)
    -- Nothing of Color Name draws on the kit's host: hide the tints and border
    -- copies a Missing row left there in another mode, or they show again
    -- whenever the gate opens for the name's own Missing rows.
    HideLooks(colorKit)
    local kitKey = NameKit(backing, colorKit)
    local b = { config = settings, kit = colorKit, nameKit = kitKey, containers = {} }
    colorKit.used = 0
    local sensorOf = {}
    for index, e in ipairs(settings.nameEntries) do
        local channel = Chain(kitKey, index, #e.spells, e.missing and kitKey.gated or kitKey.root)
        for skinData, spell in ipairs(e.spells) do
            local s = sensorOf[spell]
            if not s then
                colorKit.used = colorKit.used + 1
                s = PointSensor(colorKit, colorKit.used, spell)
                sensorOf[spell] = s
            end
            AnchorClip(channel.clips[skinData], s, e.missing)
        end
        local fontStr = channel.copy
        fontStr:ClearAllPoints()
        fontStr:SetAllPoints(backing.name)
        fontStr:SetTextColor(e.color.r, e.color.g, e.color.b, 1)
    end
    kitKey.used = #settings.nameEntries
    for index = kitKey.used + 1, #kitKey.chains do
        kitKey.chains[index].clips[1]:Hide()
    end
    ParkSensors(colorKit)
    LevelChains(kitKey)
    bundles[backing] = b
    return b
end

-- The tints share one frame level (the target/focus/hover patterns sit one
-- level up), so a later-declared slot draws on top: ReadConfig orders them.
local function CreateBundle(backing)
    if settings.name then
        return CreateNameBundle(backing)
    end
    local b = {
        config = settings,
        fill = backing.health:GetStatusBarTexture(),
        mask = backing._absorbMask,
        level = backing.health:GetFrameLevel(),
        containers = {},
        kit = settings.anyMissing and Kit(backing) or nil,
    }
    -- Tint shares the fill's frame level; CUI's text, target/focus patterns,
    -- border and absorb effects keep their own higher layers.
    b.holder = CreateFrame("Frame", nil, backing.health)
    b.holder:SetAllPoints(backing.health)
    b.holder:SetFrameLevel(b.level)
    b.holder:EnableMouse(false)
    b.holder:Hide()
    local root = CreateTintContainer(b, b.holder)
    local colorKit = b.kit
    if colorKit then
        colorKit.used = 0
        colorKit.host:SetFrameLevel(b.level)
        HideLooks(colorKit)
    end
    for index, single in ipairs(settings.singles) do
        if single.missing then
            colorKit.used = colorKit.used + 1
            DressLook(b, PointSensor(colorKit, colorKit.used, single.spell), single.color, single.sublevel)
        else
            AddTintSlot(
                b,
                root,
                "CUI_DEBUFF_COLOR_" .. index,
                single.spell,
                ColorInit(b, single.color, single.sublevel)
            )
        end
    end
    if colorKit then
        ParkSensors(colorKit)
    end
    for index, run in ipairs(settings.comboRuns) do
        AddComboRun(b, root, "CUI_DEBUFF_COMBO_" .. index, run)
    end
    bundles[backing] = b
    return b
end

-------------------------------------------------------------------------------
-- Bad threat: the plate's threat colors as UpdateHealthColor reads them, one
-- alpha per channel, 1 while nothing is wrong, 0 on bad threat (a non-tank with
-- or near aggro, a tank without or losing it), or the off-tank fold's secret
-- answer where only another tank's hold decides. The coloring yields where that
-- threat color shows under it: the health bar for the tints, the Threat Colors
-- border for Color Border, their name for Color Name. Kept on the plate (ours)
-- so a bundle built later takes it; an alpha, not a hide, so the containers
-- keep their aura data.
-------------------------------------------------------------------------------
local function ApplyThreat(b, backing)
    local a
    if b.config.channel == "border" then
        a = backing._dcThreatB
    elseif b.config.channel == "name" then
        a = backing._dcThreatN
    else
        a = backing._dcThreatH
    end
    if type(a) == "nil" then
        a = 1
    end
    if issecretvalue(a) then
        b.threatA = nil
    elseif a == b.threatA then
        return
    else
        b.threatA = a
    end
    if b.holder then
        b.holder:SetAlpha(a)
    end
    if b.kit then
        b.kit.host:SetAlpha(a)
    end
    if b.nameKit then
        b.nameKit.root:SetAlpha(a)
    end
end

local function Threat(backing, healthA, borderA, nameA)
    backing._dcThreatH, backing._dcThreatB, backing._dcThreatN = healthA, borderA, nameA
    local b = bundles[backing]
    if b then
        ApplyThreat(b, backing)
    end
end

local function Attach(backing, unitToken)
    local b = bundles[backing] or CreateBundle(backing)
    if b.nameKit then
        BindKit(b.kit, unitToken)
        b.nameKit.attached = true
        MirrorName(backing)
        ApplyThreat(b, backing)
        return
    end
    -- Parent level changes propagate to all descendants. Touch only the ordinary
    -- holder; a nested container inherits its secure AuraButton's restrictions.
    b.level = backing.health:GetFrameLevel()
    b.holder:SetFrameLevel(b.level)
    if b.kit then
        BindKit(b.kit, unitToken)
    end
    BindBundle(b, unitToken)
    ApplyThreat(b, backing)
end

-- Parking is a hide, at once even while a parse is pending; the containers
-- keep their binding (see BindBundle). The plate's threat state is the last
-- unit's: its next one arrives with UpdateHealthColor.
local function Detach(backing)
    backing._dcThreatH, backing._dcThreatB, backing._dcThreatN = nil, nil, nil
    local b = bundles[backing]
    if not b then
        return
    end
    if b.holder then
        b.holder:Hide()
    end
    if b.nameKit then
        b.nameKit.attached = nil
        b.nameKit.root:Hide()
    end
    if b.kit then
        ParkKit(b.kit)
    end
end

local function EnsureWorker()
    if job then
        return job
    end
    job = CreateFrame("Frame")
    job:Hide()
    -- PLAYER_REGEN_ENABLED, held only while a combat-deferred refresh waits;
    -- DISPLAY_SIZE_CHANGED, held only while border strips are built (they are
    -- sized in physical pixels, so a resolution change redraws them);
    -- GROUP_ROSTER_UPDATE and UNIT_PET (yours or your group's), held only while
    -- a Missing row exists (who counts as engaged).
    job:SetScript("OnEvent", function(self, evt, unitToken)
        if evt == "DISPLAY_SIZE_CHANGED" then
            mod.DebuffColors_RequestRefresh()
            return
        elseif
            evt == "UNIT_PET"
            and unitToken ~= "player"
            and not (unitToken or ""):find("^party%d")
            and not (unitToken or ""):find("^raid%d")
        then
            return
        elseif evt == "GROUP_ROSTER_UPDATE" or evt == "UNIT_PET" then
            RequestResync()
            return
        end
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if pendingRefresh then
            mod.DebuffColors_Refresh()
        end
    end)
    return job
end

function mod.DebuffColors_Refresh()
    if not settings and Value("debuffColorsEnabled") ~= true then
        return
    end
    -- Profile/spec swaps can arrive in combat. Rebuilding secure decoration is
    -- deferred; the new configuration is applied on PLAYER_REGEN_ENABLED.
    if InCombatLockdown() then
        pendingRefresh = true
        EnsureWorker():RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    pendingRefresh = false
    local nextConfig = ReadConfig()
    if settings and settings.fingerprint == nextConfig.fingerprint then
        return
    end
    settings = nextConfig
    -- Clear active AND currently pooled bundles so a later plate reuse cannot bind
    -- a previous profile's spells or colors.
    for backing, b in pairs(bundles) do
        ReleaseBundle(b)
        bundles[backing] = nil
    end
    if settings.enabled and settings.any then
        settings.comboRuns = GroupComboRuns(settings.combos)
        if settings.name then
            settings.nameEntries = NameEntries(settings)
        end
        local AK = CludesUI.AuraKit
        AK.styles[STYLE] = AK.styles[STYLE] or { noRegions = true, noTooltips = true }
        mod.DebuffColors_Attach, mod.DebuffColors_Detach = Attach, Detach
        mod.DebuffColors_Threat = Threat
        mod.DebuffColors_NameChanged = settings.name and MirrorName or nil
        for unitToken, backing in pairs(mod.plates) do
            Attach(backing, unitToken)
        end
        -- Every plate's threat state, read again now that the bundles take it.
        for _, backing in pairs(mod.plates) do
            backing:UpdateHealthColor()
        end
    else
        -- Nothing to color: no plate hooks. An enabled config stays as the
        -- applied state the next refresh compares against.
        mod.DebuffColors_Attach, mod.DebuffColors_Detach = nil, nil
        mod.DebuffColors_Threat, mod.DebuffColors_NameChanged = nil, nil
        if not settings.enabled then
            settings = nil
        end
        if job then
            job:UnregisterEvent("PLAYER_REGEN_ENABLED")
            job:SetScript("OnUpdate", nil)
            job:Hide()
        end
    end
    -- A border color is drawn in whole pixels, on the grid its key names: slices
    -- rebuild through the shared re-apply on a UI scale change, strips on a
    -- resolution change.
    local border = settings and settings.any and settings.border
    CludesUI.RegisterPxReapply(
        DC,
        (border and border.kind == "slices") and mod.DebuffColors_RequestRefresh or nil
    )
    engagersStale = true
    local watchRoster = settings and settings.any and settings.anyMissing
    for _, evt in ipairs({ "GROUP_ROSTER_UPDATE", "UNIT_PET" }) do
        if watchRoster then
            EnsureWorker():RegisterEvent(evt)
        elseif job then
            job:UnregisterEvent(evt)
        end
    end
    if not watchRoster and resync then
        resync:SetScript("OnUpdate", nil)
        resync:Hide()
    end
    if border and border.kind == "strips" then
        EnsureWorker():RegisterEvent("DISPLAY_SIZE_CHANGED")
    elseif job then
        job:UnregisterEvent("DISPLAY_SIZE_CHANGED")
    end
end

local function RunRequestedRefresh(self)
    self:Hide()
    self:SetScript("OnUpdate", nil)
    mod.DebuffColors_Refresh()
end

-- Coalesce settings writes into one next-frame refresh; never poll aura state.
-- The options page applies every edit through here as it is made. A slider
-- drag commits every step, and a border number change rebuilds every plate's
-- bundle, so while one is dragged the refresh waits for its release (the
-- slider runs the deferred checks once).
function mod.DebuffColors_RequestRefresh()
    if not settings and Value("debuffColorsEnabled") ~= true then
        return
    end
    if CludesUI._sliderDragging then
        local checks = CludesUI._deferredDriftChecks
        if not checks then
            checks = {}
            CludesUI._deferredDriftChecks = checks
        end
        checks[mod.DebuffColors_RequestRefresh] = true
        return
    end
    local wid = EnsureWorker()
    wid:SetScript("OnUpdate", RunRequestedRefresh)
    wid:Show()
end
