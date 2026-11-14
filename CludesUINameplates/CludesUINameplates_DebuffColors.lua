if CUI_CLIENT_BLOCKED then
    return
end
local _, mod = ...

-- CUI_DEBUFF_COLORS: declarative aura slots own visibility. Never read aura
-- payloads, inspect secure button visibility, or infer debuffs from casts.
local bundles = {} -- plate -> its tint bundle (reused when its unit changes)
local config
local worker
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

local function Value(key)
    local p = mod.NP_GetProfile()
    if p and p[key] ~= nil then
        return p[key]
    end
    return mod.defaults[key]
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

local function ParseColor(s, d)
    local r, g, b = s:match("^([%d%.]+),([%d%.]+),([%d%.]+)$")
    r, g, b = tonumber(r), tonumber(g), tonumber(b)
    if not (r and g and b) then
        return { r = d.r, g = d.g, b = d.b }
    end
    return { r = math.min(r, 1), g = math.min(g, 1), b = math.min(b, 1) }
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
    local singles, combos = {}, {}
    if type(s) ~= "string" then
        return singles, combos
    end
    local singlePart, comboPart = s:match("^([^/]*)/?(.*)$")
    for record in singlePart:gmatch("[^;]+") do
        if #singles == DC.MAX_SINGLES then
            break
        end
        local miss, ident, color = record:match("^(!?)(%d*):?(.*)$")
        singles[#singles + 1] = {
            spell = DC.SpellID(ident) or 0,
            color = ParseColor(color, DC.SINGLE_COLOR),
            missing = miss == "!" or nil,
        }
    end
    for record in comboPart:gmatch("[^;]+") do
        if #combos == DC.MAX_COMBOS then
            break
        end
        local ids, color = record:match("^([%d%+]*):?(.*)$")
        local spells = {}
        for ident in ids:gmatch("%d+") do
            ident = DC.SpellID(ident)
            if ident and #spells < DC.MAX_COMBO_SPELLS then
                spells[#spells + 1] = ident
            end
        end
        combos[#combos + 1] = { spells = spells, color = ParseColor(color, DC.COMBO_COLOR) }
    end
    return singles, combos
end

-- The string to save (nil once both lists are empty).
function DC.Encode(singles, combos)
    if #singles == 0 and #combos == 0 then
        return nil
    end
    local s, c = {}, {}
    for idx, e in ipairs(singles) do
        s[idx] = (e.missing and "!" or "") .. e.spell .. ":" .. ColorText(e.color)
    end
    for idx, e in ipairs(combos) do
        c[idx] = table.concat(e.spells, "+") .. ":" .. ColorText(e.color)
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

local function Distinct(spells)
    local result, seen = {}, {}
    for _, ident in ipairs(spells) do
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
        local tex = Value("customBorderTexture")
        local size = Value("customBorderSize") or 0
        if size <= 0 then
            return nil
        end
        local px = CludesUI.BorderPx(Value("customBorderSizePx"), size, tex)
        -- On MEDIUM strata. The border frame sits one level above the bar (one
        -- below it when drawn behind); a textured border draws on that frame,
        -- a Solid one on the pixel border's container one level higher. The
        -- color goes one level above whichever draws: up = levels above the
        -- border frame (MakeBorderInit places that frame's level).
        local behind = Value("customBorderBehind") == true
        if not tex or tex == "" or tex == "solid" then
            s = {
                kind = "strips",
                px = (px or size) + ExtraBorderPx(),
                strata = "MEDIUM",
                behind = behind,
                up = 2,
            }
        else
            local filePath = CludesUI.ResolveBorderTexture(tex)
            if not filePath then
                return nil
            end
            s = {
                kind = "slices",
                path = filePath,
                tex = tex,
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
    local singles, combos = DC.Read(class or "")
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
        local key = Value("healthBarTexture")
        if mode == "texture" then
            key = Value("debuffColorsTexture") or key
        end
        c.texture = CludesUI.ResolveTexturePath(mod.healthBarTextures, key, WHITE)
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
        local key = (e.missing and "!" or "") .. e.spell
        if e.spell > 0 and not seen[key] and not (e.missing and missing == DC.MAX_MISSING) then
            seen[key] = true
            ranked[#ranked + 1] = e
            if e.missing then
                missing = missing + 1
                e.sublevel = -3 - missing
            end
        end
    end
    for idx = #ranked, 1, -1 do
        local e = ranked[idx]
        c.singles[#c.singles + 1] = {
            spell = e.spell,
            color = e.color,
            sublevel = e.sublevel or (idx == 1 and 5) or 4,
            missing = e.missing,
        }
        parts[#parts + 1] = (e.missing and "m" or "s") .. e.spell .. ":" .. ColorText(e.color)
        if e.missing then
            c.anyMissing = true
        end
    end
    for idx = #combos, 1, -1 do
        local spells = Distinct(combos[idx].spells)
        if #spells >= 2 then
            c.combos[#c.combos + 1] = { spells = spells, color = combos[idx].color }
            parts[#parts + 1] = "c" .. table.concat(spells, "+") .. ":" .. ColorText(combos[idx].color)
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
local function GroupComboRuns(combos)
    local runs, idx = {}, 1
    while idx <= #combos do
        local common = {}
        for _, ident in ipairs(combos[idx].spells) do
            common[ident] = true
        end
        local jdx = idx
        while jdx < #combos do
            local both, any = {}, false
            for _, ident in ipairs(combos[jdx + 1].spells) do
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
        for _, ident in ipairs(combos[idx].spells) do
            if common[ident] then
                first = ident
                break
            end
        end
        local run = {}
        for k = idx, jdx do
            local spells = { first }
            for _, ident in ipairs(combos[k].spells) do
                if ident ~= first then
                    spells[#spells + 1] = ident
                end
            end
            run[#run + 1] = { spells = spells, color = combos[k].color }
        end
        runs[#runs + 1] = run
        idx = jdx + 1
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
        for idx = 1, 40 do
            groupTokens.raid[idx], groupTokens.raidpet[idx] = "raid" .. idx, "raidpet" .. idx
        end
        for idx = 1, 4 do
            groupTokens.party[idx], groupTokens.partypet[idx] = "party" .. idx, "partypet" .. idx
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
        for idx = 1, math.min(GetNumGroupMembers() - (raid and 0 or 1), #who) do
            if not UnitIsUnit(who[idx], "player") then
                num = num + 1
                engagers[num] = who[idx]
                if UnitExists(pets[idx]) then
                    num = num + 1
                    engagers[num] = pets[idx]
                end
            end
        end
        for idx = #engagers, num + 1, -1 do
            engagers[idx] = nil
        end
    end
    for idx = 1, #engagers do
        if type(UnitThreatSituation(engagers[idx], unitToken)) ~= "nil" then
            return true
        end
    end
    return false
end

-- Shown on an engaged enemy: an assistable unit's debuffs cannot be spell-filtered.
-- nameGated: Color Name's Missing rows (see NameKit).
local function SyncGate(kit)
    local open = not UnitCanAssist("player", kit.unit, true, true) and Engaged(kit.unit)
    if open ~= kit.open then
        kit.open = open
        kit.gate:SetShown(open)
        if kit.nameGated then
            kit.nameGated:SetShown(open)
        end
    end
end

local function RunResync(self)
    self:Hide()
    self:SetScript("OnUpdate", nil)
    for _, kit in pairs(kits) do
        if kit.unit then
            SyncGate(kit)
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
    local kit = kits[backing]
    if kit then
        return kit
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
    local host = CreateFrame("Frame", nil, gate)
    host:SetAllPoints(gate)
    kit = { gate = gate, hider = hider, host = host, sensors = {}, looks = {}, used = 0 }
    gate:SetScript("OnEvent", function()
        SyncGate(kit)
    end)
    kits[backing] = kit
    return kit
end

-- Sensor n, pointed at spell. Its mask takes two anchors and a width: a single
-- point and a size draws displaced inside the plate (see PlaceArrow).
local function PointSensor(kit, num, spell)
    local AK = CludesUI.AuraKit
    local filter, ids = AK.Filter(unpack(config.filterTokens)), { includeSpellIDs = { [spell] = true } }
    local s = kit.sensors[num]
    if not s then
        local c = AK.CreateContainerShell(
            kit.hider,
            { point = { "TOPLEFT", kit.hider, "TOPLEFT", -(REACH + 1), REACH } }
        )
        AK.AddGroupToContainer(c, {
            key = SENSOR_KEY,
            filter = config.filterTokens,
            maxFrameCount = 1,
            style = STYLE,
            candidateFilters = ids,
            layout = { elementWidth = SPAN, elementHeight = 1 },
            extraInit = function(btnFrame)
                btnFrame:EnableMouse(false)
            end,
        })
        local mask = kit.gate:CreateMaskTexture()
        mask:SetTexture(WHITE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetPoint("TOPLEFT", c, "TOPRIGHT", 0, 0)
        mask:SetPoint("BOTTOMLEFT", c, "BOTTOMRIGHT", 0, 1 - SPAN)
        mask:SetWidth(SPAN)
        s = { container = c, mask = mask, n = num }
        kit.sensors[num] = s
    elseif s.spell ~= spell or s.filter ~= filter then
        s.container:SetAuraGroupFilterString(SENSOR_KEY, filter)
        s.container:SetAuraGroupCandidateFilters(SENSOR_KEY, ids)
    end
    s.spell, s.filter = spell, filter
    AK.SetGroupCap(s.container, SENSOR_KEY, 1)
    return s
end

-- Sensors the bundle did not use are switched off (no UNIT_AURA work).
local function ParkSensors(kit)
    for num = kit.used + 1, #kit.sensors do
        CludesUI.AuraKit.SetGroupCap(kit.sensors[num].container, SENSOR_KEY, 0)
    end
end

-- The gate's events only while a Missing row reads it (Color Name binds a kit
-- for its sensors alone).
local function BindKit(kit, unitToken)
    for num = 1, kit.used do
        local s = kit.sensors[num]
        if s.unit ~= unitToken then
            s.unit = unitToken
            s.container:SetUnit(unitToken)
        end
    end
    kit.hider:Show()
    kit.unit, kit.open = unitToken, nil
    if config.anyMissing then
        kit.gate:RegisterUnitEvent("UNIT_FLAGS", unitToken)
        kit.gate:RegisterUnitEvent("UNIT_THREAT_LIST_UPDATE", unitToken)
        SyncGate(kit)
    end
end

local function ParkKit(kit)
    kit.unit, kit.open = nil, nil
    kit.gate:UnregisterAllEvents()
    kit.gate:Hide()
    kit.hider:Hide()
    if kit.nameGated then
        kit.nameGated:Hide()
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
        local idx = 1
        while idx <= #b.containers do
            b.containers[idx]:SetUnit(unitToken)
            idx = idx + 1
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
local function PaintTint(tint, b, color)
    tint:SetTexture(b.config.texture)
    tint:SetVertexColor(color.r, color.g, color.b, 1)
    tint:ClearAllPoints()
    tint:SetPoint("TOPLEFT", b.fill, "TOPLEFT", 0, 0)
    tint:SetPoint("BOTTOMRIGHT", b.fill, "BOTTOMRIGHT", 0, 0)
end

local function MakeTintInit(b, color, sublevel)
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
        local tint = btnFrame:CreateTexture(nil, "ARTWORK", nil, sublevel)
        PaintTint(tint, b, color)
        if b.mask then
            tint:AddMaskTexture(b.mask)
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
    local f = CreateFrame("Frame", nil, hostFrame)
    f:EnableMouse(false)
    if specInfo.strata then
        f:SetFrameStrata(specInfo.strata)
    end
    local mask
    if sensorMask then
        mask = f:CreateMaskTexture()
        mask:SetTexture(WHITE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(sensorMask)
    end
    local pieces = {}
    if specInfo.kind == "strips" then
        f:SetIgnoreParentScale(true)
        f:SetScale(1)
        for idx = 1, 4 do
            local tx = f:CreateTexture(nil, "OVERLAY")
            if tx.SetSnapToPixelGrid then
                tx:SetSnapToPixelGrid(false)
                tx:SetTexelSnappingBias(0)
            end
            pieces[idx] = tx
        end
    else
        for key, coords in pairs(CludesUI.SECRET_BORDER_UV) do
            local tx = f:CreateTexture(nil, "OVERLAY")
            tx:SetTexCoord(unpack(coords))
            pieces[key] = tx
        end
    end
    if mask then
        for _, tx in pairs(pieces) do
            tx:AddMaskTexture(mask)
        end
    end
    return f, pieces
end

local function LayStrip(tx, f, p1, y1, p2, y2, width, height)
    tx:SetPoint(p1, f, p1, 0, y1)
    tx:SetPoint(p2, f, p2, 0, y2)
    if width then
        tx:SetWidth(width)
    else
        tx:SetHeight(height)
    end
end

-- Colors a copy and lays it over owner (the bar's rect), on OVERLAY sublevel.
local function DressBorderCopy(f, pieces, specInfo, ownerFrame, color, sublevel)
    f:ClearAllPoints()
    f:SetAllPoints(ownerFrame)
    for _, tx in pairs(pieces) do
        tx:SetDrawLayer("OVERLAY", sublevel)
        tx:ClearAllPoints()
    end
    if specInfo.kind == "strips" then
        local success, es = pcall(f.GetEffectiveScale, f)
        if not (success and es and es > 0) then
            es = 1
        end
        local one = CludesUI.PP.perfect / es
        local t = math.max(one, math.floor(specInfo.px + 0.5) * one)
        for _, tx in ipairs(pieces) do
            tx:SetColorTexture(color.r, color.g, color.b, 1)
        end
        LayStrip(pieces[1], f, "TOPLEFT", 0, "TOPRIGHT", 0, nil, t)
        LayStrip(pieces[2], f, "BOTTOMLEFT", 0, "BOTTOMRIGHT", 0, nil, t)
        LayStrip(pieces[3], f, "TOPLEFT", -t, "BOTTOMLEFT", t, t)
        LayStrip(pieces[4], f, "TOPRIGHT", -t, "BOTTOMRIGHT", t, t)
    else
        for _, tx in pairs(pieces) do
            tx:SetTexture(specInfo.path, true, true)
            tx:SetVertexColor(color.r, color.g, color.b, 1)
        end
        local edge, aL, aT, aR, aB = CludesUI.SecretBorderGeometry(
            f,
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
        CludesUI.LayoutSecretBorderEdges(pieces, f, edge, aL, aT, aR, aB)
    end
end

-- A slot's copy, built in the creation window only.
local function MakeBorderInit(b, color, sublevel)
    local initialized = setmetatable({}, { __mode = "k" })
    local rank = 0
    if not b.config.border.strata then
        rank = (sublevel == 7 and 2) or (sublevel == 5 and 1) or 0
        sublevel = 7
    end
    return function(btnFrame)
        if initialized[btnFrame] then
            return
        end
        initialized[btnFrame] = true
        btnFrame:SetFrameLevel(b.level)
        btnFrame:EnableMouse(false)
        local specInfo = b.config.border
        local f, pieces = NewBorderCopy(btnFrame, specInfo)
        f:SetFrameLevel(CopyLevel(b, specInfo, rank))
        DressBorderCopy(f, pieces, specInfo, b.holder, color, sublevel)
    end
end

-- What a slot shows while its debuffs are up: the health fill's tint (Color
-- Nameplate) or the border in the color (Color Border).
local function ColorInit(b, color, sublevel)
    if b.config.border then
        return MakeBorderInit(b, color, sublevel)
    end
    return MakeTintInit(b, color, sublevel)
end

-- Missing row n draws on the kit's host through sensor n's mask: a tint on
-- OVERLAY at the bar's level (one higher draws over the border), or a copy
-- ranked over every other copy by n. These frames are ours, unlike the slots'
-- engine buttons, so each is built once (a copy once per border style) and
-- dressed again on every rebuild.
local function DressLook(b, sensor, color, sublevel)
    local kit, num = b.kit, sensor.n
    local look = kit.looks[num]
    if not look then
        look = { copies = {} }
        kit.looks[num] = look
    end
    local specInfo = b.config.border
    if not specInfo then
        local tint = look.tint
        if not tint then
            tint = kit.host:CreateTexture(nil, "OVERLAY")
            if b.mask then
                tint:AddMaskTexture(b.mask)
            end
            tint:AddMaskTexture(sensor.mask)
            look.tint = tint
        end
        tint:SetDrawLayer("OVERLAY", sublevel)
        PaintTint(tint, b, color)
        tint:Show()
        return
    end
    local rank = 0
    if not specInfo.strata then
        rank, sublevel = 2, 7
    end
    local style = specInfo.kind .. (specInfo.strata or "")
    local copy = look.copies[style]
    if not copy then
        local f, pieces = NewBorderCopy(kit.host, specInfo, sensor.mask)
        copy = { frame = f, pieces = pieces }
        look.copies[style] = copy
    end
    copy.frame:SetFrameLevel(CopyLevel(b, specInfo, rank) + num)
    DressBorderCopy(copy.frame, copy.pieces, specInfo, kit.host, color, sublevel)
    copy.frame:Show()
end

local function HideLooks(kit)
    for _, look in ipairs(kit.looks) do
        if look.tint then
            look.tint:Hide()
        end
        for _, copy in pairs(look.copies) do
            copy.frame:Hide()
        end
    end
end

local function AddTintSlot(b, boxHolder, key, spell, initialize)
    CludesUI.AuraKit.AddSlotToContainer(boxHolder, {
        key = key,
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
local function AddComboSlot(b, boxHolder, key, combo, depth)
    local spell = combo.spells[depth]
    if depth == #combo.spells then
        AddTintSlot(b, boxHolder, key .. "_" .. depth, spell, ColorInit(b, combo.color, 7))
        return
    end
    AddTintSlot(
        b,
        boxHolder,
        key .. "_" .. depth,
        spell,
        MakeNestInit(b, function(nested)
            AddComboSlot(b, nested, key, combo, depth + 1)
        end)
    )
end

-- A run's combos share their first slot; its nested container holds the rest
-- of each combo, declared bottom to top like the runs themselves.
local function AddComboRun(b, boxHolder, key, run)
    AddTintSlot(
        b,
        boxHolder,
        key,
        run[1].spells[1],
        MakeNestInit(b, function(nested)
            for idx, combo in ipairs(run) do
                AddComboSlot(b, nested, key .. "_" .. idx, combo, 2)
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
local function NameKit(backing, kit)
    local nk = nameKits[backing]
    if not nk then
        local root = CreateFrame("Frame", nil, backing, "DisableUntrustedLayoutScriptsTemplate")
        root:SetAllPoints(backing.health)
        root:Hide()
        local gated = CreateFrame("Frame", nil, root)
        gated:SetAllPoints(root)
        nk = { root = root, gated = gated, chains = {}, used = 0 }
        nameKits[backing] = nk
    end
    kit.nameGated = nk.gated
    nk.gated:SetShown(kit.open == true)
    return nk
end

-- Row i's chain: depth clips, each inside the last, the copy in the innermost.
-- Pooled by index; a row that needs more clips adds them.
local function Chain(nk, idx, depth, hostFrame)
    local ch = nk.chains[idx]
    if not ch then
        ch = { clips = {} }
        nk.chains[idx] = ch
    end
    local clips = ch.clips
    for d = 1, depth do
        local wanted = (d == 1) and hostFrame or clips[d - 1]
        local clip = clips[d]
        if not clip then
            clip = CreateFrame("Frame", nil, wanted)
            clip:SetClipsChildren(true)
            clips[d] = clip
        elseif clip:GetParent() ~= wanted then
            clip:SetParent(wanted)
        end
        clip:Show()
    end
    for d = depth + 1, #clips do
        clips[d]:Hide()
    end
    ch.depth = depth
    local inner = clips[depth]
    if not ch.copy then
        ch.copy = inner:CreateFontString(nil, "OVERLAY")
    elseif ch.copy:GetParent() ~= inner then
        ch.copy:SetParent(inner)
    end
    return ch
end

-- A clip open while its debuff is up (the sensor's container SPAN wide), or
-- for a Missing row while it is absent (a single pixel; the mask's placement).
local function AnchorClip(clip, sensor, missing)
    local c = sensor.container
    clip:ClearAllPoints()
    if missing then
        clip:SetPoint("TOPLEFT", c, "TOPRIGHT", 0, CLIP_REACH)
        clip:SetPoint("BOTTOMLEFT", c, "BOTTOMRIGHT", 0, -CLIP_REACH)
        clip:SetWidth(SPAN)
    else
        clip:SetPoint("TOPLEFT", c, "TOPLEFT", 0, CLIP_REACH)
        clip:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, -CLIP_REACH)
    end
end

-- A later row draws over an earlier one, every row over the name itself. Each
-- frame takes the root's strata itself, parents first: on the flattened plate a
-- frame that only inherits it renders in the plate's own batch, under the name,
-- and a parent's strata change resets its children's strata and levels.
local function LevelChains(nk)
    local strata, base = nk.root:GetFrameStrata(), nk.root:GetFrameLevel()
    nk.gated:SetFrameStrata(strata)
    nk.gated:SetFrameLevel(base)
    for idx = 1, nk.used do
        local ch = nk.chains[idx]
        for d = 1, ch.depth do
            local clip = ch.clips[d]
            clip:SetFrameStrata(strata)
            clip:SetFrameLevel(base + (idx - 1) * CHAIN_STEP + d)
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
    local nk = b and b.nameKit
    if not nk then
        return
    end
    local name, root = backing.name, nk.root
    root:SetShown(nk.attached == true and name:IsShown())
    if shownOnly then
        return
    end
    -- The host's own strata change (SlotTextHost) reaches its children, so the
    -- strata and levels are set again on every pass.
    local host = name:GetParent()
    if root:GetParent() ~= host then
        root:SetParent(host)
    end
    root:SetFrameStrata(host:GetFrameStrata())
    root:SetFrameLevel(host:GetFrameLevel() + 1)
    LevelChains(nk)
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
    for idx = 1, nk.used do
        local fontStr = nk.chains[idx].copy
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
    local kit = Kit(backing)
    -- Nothing of Color Name draws on the kit's host: hide the tints and border
    -- copies a Missing row left there in another mode, or they show again
    -- whenever the gate opens for the name's own Missing rows.
    HideLooks(kit)
    local nk = NameKit(backing, kit)
    local b = { config = config, kit = kit, nameKit = nk, containers = {} }
    kit.used = 0
    local sensorOf = {}
    for idx, e in ipairs(config.nameEntries) do
        local ch = Chain(nk, idx, #e.spells, e.missing and nk.gated or nk.root)
        for d, spell in ipairs(e.spells) do
            local s = sensorOf[spell]
            if not s then
                kit.used = kit.used + 1
                s = PointSensor(kit, kit.used, spell)
                sensorOf[spell] = s
            end
            AnchorClip(ch.clips[d], s, e.missing)
        end
        local fontStr = ch.copy
        fontStr:ClearAllPoints()
        fontStr:SetAllPoints(backing.name)
        fontStr:SetTextColor(e.color.r, e.color.g, e.color.b, 1)
    end
    nk.used = #config.nameEntries
    for idx = nk.used + 1, #nk.chains do
        nk.chains[idx].clips[1]:Hide()
    end
    ParkSensors(kit)
    LevelChains(nk)
    bundles[backing] = b
    return b
end

-- The tints share one frame level (the target/focus/hover patterns sit one
-- level up), so a later-declared slot draws on top: ReadConfig orders them.
local function CreateBundle(backing)
    if config.name then
        return CreateNameBundle(backing)
    end
    local b = {
        config = config,
        fill = backing.health:GetStatusBarTexture(),
        mask = backing._absorbMask,
        level = backing.health:GetFrameLevel(),
        containers = {},
        kit = config.anyMissing and Kit(backing) or nil,
    }
    -- Tint shares the fill's frame level; CUI's text, target/focus patterns,
    -- border and absorb effects keep their own higher layers.
    b.holder = CreateFrame("Frame", nil, backing.health)
    b.holder:SetAllPoints(backing.health)
    b.holder:SetFrameLevel(b.level)
    b.holder:EnableMouse(false)
    b.holder:Hide()
    local root = CreateTintContainer(b, b.holder)
    local kit = b.kit
    if kit then
        kit.used = 0
        kit.host:SetFrameLevel(b.level)
        HideLooks(kit)
    end
    for idx, single in ipairs(config.singles) do
        if single.missing then
            kit.used = kit.used + 1
            DressLook(b, PointSensor(kit, kit.used, single.spell), single.color, single.sublevel)
        else
            AddTintSlot(
                b,
                root,
                "CUI_DEBUFF_COLOR_" .. idx,
                single.spell,
                ColorInit(b, single.color, single.sublevel)
            )
        end
    end
    if kit then
        ParkSensors(kit)
    end
    for idx, run in ipairs(config.comboRuns) do
        AddComboRun(b, root, "CUI_DEBUFF_COMBO_" .. idx, run)
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
    if worker then
        return worker
    end
    worker = CreateFrame("Frame")
    worker:Hide()
    -- PLAYER_REGEN_ENABLED, held only while a combat-deferred refresh waits;
    -- DISPLAY_SIZE_CHANGED, held only while border strips are built (they are
    -- sized in physical pixels, so a resolution change redraws them);
    -- GROUP_ROSTER_UPDATE and UNIT_PET (yours or your group's), held only while
    -- a Missing row exists (who counts as engaged).
    worker:SetScript("OnEvent", function(self, evt, unitToken)
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
    return worker
end

function mod.DebuffColors_Refresh()
    if not config and Value("debuffColorsEnabled") ~= true then
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
    if config and config.fingerprint == nextConfig.fingerprint then
        return
    end
    config = nextConfig
    -- Clear active AND currently pooled bundles so a later plate reuse cannot bind
    -- a previous profile's spells or colors.
    for backing, b in pairs(bundles) do
        ReleaseBundle(b)
        bundles[backing] = nil
    end
    if config.enabled and config.any then
        config.comboRuns = GroupComboRuns(config.combos)
        if config.name then
            config.nameEntries = NameEntries(config)
        end
        local AK = CludesUI.AuraKit
        AK.styles[STYLE] = AK.styles[STYLE] or { noRegions = true, noTooltips = true }
        mod.DebuffColors_Attach, mod.DebuffColors_Detach = Attach, Detach
        mod.DebuffColors_Threat = Threat
        mod.DebuffColors_NameChanged = config.name and MirrorName or nil
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
        if not config.enabled then
            config = nil
        end
        if worker then
            worker:UnregisterEvent("PLAYER_REGEN_ENABLED")
            worker:SetScript("OnUpdate", nil)
            worker:Hide()
        end
    end
    -- A border color is drawn in whole pixels, on the grid its key names: slices
    -- rebuild through the shared re-apply on a UI scale change, strips on a
    -- resolution change.
    local border = config and config.any and config.border
    CludesUI.RegisterPxReapply(
        DC,
        (border and border.kind == "slices") and mod.DebuffColors_RequestRefresh or nil
    )
    engagersStale = true
    local watchRoster = config and config.any and config.anyMissing
    for _, evt in ipairs({ "GROUP_ROSTER_UPDATE", "UNIT_PET" }) do
        if watchRoster then
            EnsureWorker():RegisterEvent(evt)
        elseif worker then
            worker:UnregisterEvent(evt)
        end
    end
    if not watchRoster and resync then
        resync:SetScript("OnUpdate", nil)
        resync:Hide()
    end
    if border and border.kind == "strips" then
        EnsureWorker():RegisterEvent("DISPLAY_SIZE_CHANGED")
    elseif worker then
        worker:UnregisterEvent("DISPLAY_SIZE_CHANGED")
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
    if not config and Value("debuffColorsEnabled") ~= true then
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
