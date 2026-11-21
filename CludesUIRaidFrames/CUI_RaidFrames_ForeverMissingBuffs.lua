if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_RaidFrames_ForeverMissingBuffs.lua  (WoW Forever only)
--
--  Missing Buffs indicator: on each raid, party and Extra Frames button, the
--  icon of every buff the member lacks that the PLAYER can cast --
--  Fortitude and Spirit (priest; Spirit needs the Divine Spirit talent),
--  Mark of the Wild and Thorns (druid), Arcane Intellect (mage; on mana users
--  only), Salvation and a paladin blessing --
--  i.e. a trained rank or the group version is in the player's spellbook. On
--  the member every rank and the group version count (looked up by name). A
--  member gets at most one blessing: the first of the priority list their
--  assigned role takes (Tank / Healer / DPS Blessing; empty = no reminder; no
--  role assigned = the DPS list) that the player can cast and the member
--  lacks. Solo, only Kings is reminded, on the player, whatever the role.
--  Salvation stacks with a blessing since build 70425, so it has a switch of
--  its own and shows on every group member but a tank (never solo). Thorns
--  Only on Tank keeps Thorns to the group's tanks, and to the player while
--  solo or in a group without one.
--  Settings (Indicators section, same shape as the raid marker):
--  showMissingBuffs, missingBuffsPosition, missingBuffsSize,
--  missingBuffsOffsetX/Y, one switch per buff (missingBuffsFort/Mark/Intellect/
--  Spirit/Thorns/Salvation, the cog's checkbox list, nil = on), missingBuffsThornsTank
--  (nil = off), missingBuffsBlessingTank/Healer/DPS (a list of blessing keys in
--  priority order, or the older single key / "none"; unset = Might / Wisdom /
--  Might, or none for all three while the retired single switch
--  missingBuffsBlessing reads false; a saved "salvation" is skipped),
--  missingBuffsBlessingExTank/Healer/DPS
--  (class token -> blessing list, replacing the role's list for members of
--  that class; no entry = the role's list), and the icons' glow on the
--  shared prefix schema (missingBuffsGlow*, CludesUI.Glows.PrefixKeys);
--  Forever-only defaults in the main file.
--
--  A member reads as unknown (no icon) while offline or out of sight (the
--  client has no aura data then), and under the game's aura restriction a
--  buff counts only if every rank of it is non-secret at that moment
--  (C_Secrets, asked again each frame: outside a restriction nothing is
--  secret); a secret one would read absent while up, so it shows nothing
--  rather than a false alarm.
--
--  Cost: off everywhere, every buff of the player's class switched off, or
--  a class that can cast none of these buffs = no events, no overlays.
--  On: UNIT_AURA and
--  UNIT_CONNECTION for the group tokens only, each aura event probing its
--  own added and removed auras against these buffs before a member is
--  looked up again (coalesced to one pass per frame); the roster, the roles,
--  the world and each aura restriction edge re-read everyone once. While
--  auras are restricted the payload is secret, so an event re-reads its
--  member only while a buff the player provides stays readable. A secret
--  role reads as unknown: no blessing and no tank-only Thorns for it.
--
--  The main file calls ns.RF_FvMissingAnchor from each reload path and
--  ns.RF_FvMissingPreview from the preview pass, the containers file
--  ns.RF_FvMissingUnit from the secure header's unit assignment; on every
--  other client all three stay nil.
-------------------------------------------------------------------------------
local _, mod = ...
local CUI = _G.CludesUI
if not (CUI and CUI.IS_FOREVER) then return end

-- One entry per buff, shown in this order. class: the one class that casts
-- it; setting: its own switch (the cog's checkbox list; nil = on); from: the
-- shared buff families it is made of (CludesUI.FOREVER_BUFF_FAMILIES),
-- merged below into names (spells whose localized names cover every rank and
-- the group version), ranks (the player ranks and the group version: the
-- "player can cast it" and restriction tests) and ids (every spell that
-- applies the buff, for the aura-event probe).
local FAMILIES = {
    { key = "fort", class = "PRIEST", setting = "missingBuffsFort", icon = 1243, from = { "fort" } },
    { key = "mark", class = "DRUID", setting = "missingBuffsMark", icon = 1126, from = { "mark" } },
    -- Arcane Intellect and Arcane Brilliance: mana users only (the family's
    -- beneficiaries).
    { key = "intellect", class = "MAGE", setting = "missingBuffsIntellect", icon = 1459, from = { "ai" } },
    { key = "spirit", class = "PRIEST", setting = "missingBuffsSpirit", icon = 14752, from = { "spirit" } },
    -- Thorns: six druid ranks (Balance), no group version.
    {
        key = "thorns",
        class = "DRUID",
        setting = "missingBuffsThorns",
        icon = 467,
        from = { "thorns" },
        tankOnly = true,
    },
    -- Salvation and Mass Salvation: no longer a blessing (it stacks with one),
    -- never wanted on a tank.
    {
        key = "salvation",
        class = "PALADIN",
        setting = "missingBuffsSalvation",
        icon = 1038,
        from = { "salvation" },
        notTank = true,
    },
    -- The paladin blessings, normal and Greater: a member shows at most one,
    -- by role (the role settings, not a switch, pick it). The keys are the
    -- role settings' values (a saved "light", a blessing the game removed, is
    -- skipped).
    { key = "might", class = "PALADIN", blessing = true, icon = 19740, from = { "might" } },
    { key = "wisdom", class = "PALADIN", blessing = true, icon = 19742, from = { "wisdom" } },
    { key = "kings", class = "PALADIN", blessing = true, icon = 20217, from = { "kings" } },
}
local NUM_FAMILIES = #FAMILIES
for index = 1, NUM_FAMILIES do
    local fam = FAMILIES[index]
    local nameList, ranks, ids = {}, {}, {}
    for _, key in ipairs(fam.from) do
        local shared = CUI.FOREVER_BUFF_FAMILIES[key]
        for _, ident in ipairs(shared.names) do
            nameList[#nameList + 1] = ident
        end
        for _, ident in ipairs(shared.single) do
            ranks[#ranks + 1] = ident
        end
        for _, ident in ipairs(shared.group) do
            ranks[#ranks + 1] = ident
        end
        for _, ident in ipairs(shared.ids) do
            ids[#ids + 1] = ident
        end
        -- Only these classes need it (nil = everyone).
        fam.only = shared.beneficiaries
    end
    fam.names, fam.ranks, fam.ids = nameList, ranks, ids
end
local FAMILY_BY_ID = {} -- spell id -> family index
local BLESS_INDEX = {} -- blessing key -> family index
for index = 1, NUM_FAMILIES do
    for _, ident in ipairs(FAMILIES[index].ids) do
        FAMILY_BY_ID[ident] = index
    end
    if FAMILIES[index].blessing then BLESS_INDEX[FAMILIES[index].key] = index end
end

-- The blessings a role (TANK, HEALER or DAMAGER) takes in a settings table
-- (raw reads, nil = unset): a priority list of blessing keys, first = most
-- wanted (empty = none). A saved value is a list, or the older single key /
-- "none". Unset takes the role's default, or none while the retired single
-- Paladin Blessings switch reads false (its users had turned blessings off).
-- The options page reads through the same function.
local BLESS_KEY = {
    TANK = "missingBuffsBlessingTank",
    HEALER = "missingBuffsBlessingHealer",
    DAMAGER = "missingBuffsBlessingDPS",
}
local BLESS_DEFAULT = { TANK = "might", HEALER = "wisdom", DAMAGER = "might" }
-- Class exceptions: per role, a table of class token -> blessing list that
-- replaces the role's list for members of that class (an empty list = no
-- blessing for them; no entry = the role's list).
local EX_KEY = {
    TANK = "missingBuffsBlessingExTank",
    HEALER = "missingBuffsBlessingExHealer",
    DAMAGER = "missingBuffsBlessingExDPS",
}
local NO_BLESSINGS = {}
local OLD_SINGLE = {} -- the older single-key form, one cached list per key
local function Choice(cfg, role, class)
    local key = BLESS_KEY[role]
    if class then
        local ex = cfg[EX_KEY[role]]
        local own = type(ex) == "table" and ex[class]
        if type(own) == "table" then return own end
    end
    local val = cfg[key]
    if val == nil then val = (cfg.missingBuffsBlessing == false) and "none" or BLESS_DEFAULT[role] end
    if type(val) == "table" then return val end
    if not BLESS_INDEX[val] then return NO_BLESSINGS end
    local one = OLD_SINGLE[val]
    if not one then
        one = { val }
        OLD_SINGLE[val] = one
    end
    return one
end
mod.RF_FvBlessingChoice, mod.RF_FvBlessingKey, mod.RF_FvBlessingExKey = Choice, BLESS_KEY, EX_KEY

-- A list takes a blessing when it holds a key the indicator knows: a saved key
-- it skips (a blessing the game removed) does not count.
local function TakesOne(entries)
    for index = 1, #entries do
        if BLESS_INDEX[entries[index]] then return true end
    end
    return false
end

-- Blessings are on in a settings table while any role takes one, or any
-- class exception does.
local function BlessingsOn(cfg)
    if
        TakesOne(Choice(cfg, "TANK"))
        or TakesOne(Choice(cfg, "HEALER"))
        or TakesOne(Choice(cfg, "DAMAGER"))
    then
        return true
    end
    for _, key in pairs(EX_KEY) do
        local ex = cfg[key]
        if type(ex) == "table" then
            for _, entries in pairs(ex) do
                if type(entries) == "table" and TakesOne(entries) then return true end
            end
        end
    end
    return false
end

-- Only a priest, a druid, a mage or a paladin can ever cast one of these: every
-- other class keeps the whole indicator off (no events, no overlays).
local PLAYER_CLASS = select(2, UnitClass("player"))
local CAN_EVER = false
for index = 1, NUM_FAMILIES do
    if FAMILIES[index].class == PLAYER_CLASS then CAN_EVER = true end
end

-- Per group token: state[unit][key] = true (has it), false (lacks it) or nil
-- (unknown); inst[unit] = the aura instances found, for the removed-aura probe.
local status, instance = {}, {}
local provider = {} -- key -> the player can cast it (a rank in the spellbook)
local blessCaster = false -- the player can cast any blessing (the role lists then apply)
local groupTank = false -- a group member has the tank role (full passes)
local solo = true -- not in a group (full passes)
local wantFam = {} -- key -> switched on where the indicator shows (raid, party or Extra Frames)
local enabled = false
local trusted = {} -- key -> readable right now (Trusted rebuilds it once per frame)
local nameList = {} -- family index -> { localized names }
local icons = {} -- family index -> texture

local function SettingsFor(skinData)
    return skinData._isParty and mod._scaledPartyProxy
        or (skinData._isExtra and mod._scaledExtraProxy)
        or mod._scaledProfile
end

local function FamilyNames(index)
    local num = nameList[index]
    if num then return num end
    num = {}
    for _, ident in ipairs(FAMILIES[index].names) do
        local name = C_Spell.GetSpellName(ident)
        if name then num[#num + 1] = name end
    end
    -- Spell data can be cold this early: keep an empty answer uncached.
    if #num > 0 then nameList[index] = num end
    return num
end

local function FamilyIcon(index)
    local texture = icons[index]
    if not texture then
        texture = C_Spell.GetSpellTexture(FAMILIES[index].icon)
        icons[index] = texture
    end
    return texture or 134400
end

-- Whether every player rank of a buff reads non-secret right now. The
-- answer follows the current restriction (outside one no aura is secret),
-- so it is rebuilt once per frame and never kept across a restriction edge:
-- a lookup can only find a non-secret aura, so a stale "readable" turns a
-- secret buff into a false "missing".
local trustedAt
local function Trusted(index)
    local nowTime = GetTime()
    if trustedAt ~= nowTime then
        trustedAt = nowTime
        local S = C_Secrets
        for fi = 1, NUM_FAMILIES do
            local success = true
            if S and S.ShouldSpellAuraBeSecret then
                for _, ident in ipairs(FAMILIES[fi].ranks) do
                    local good, secret = pcall(S.ShouldSpellAuraBeSecret, ident)
                    if not good or issecretvalue(secret) or secret ~= false then
                        success = false
                        break
                    end
                end
            end
            trusted[FAMILIES[fi].key] = success
        end
    end
    return trusted[FAMILIES[index].key]
end

-- A buff's own switch in one settings table (nil = on); the blessings follow
-- the role settings as one.
local function FamOn(cfg, fam)
    if fam.blessing then return BlessingsOn(cfg) end
    return cfg[fam.setting] ~= false
end

-- Worth reading: the player can cast it and it is switched on somewhere. A
-- blessing the player cannot cast never shows and can never be theirs.
local function Tracked(index)
    local key = FAMILIES[index].key
    return provider[key] and wantFam[key]
end

-- The member's assigned role ("TANK", "HEALER", "DAMAGER", "NONE"), or nil
-- while it reads secret.
local function RoleOf(unitToken)
    local role = UnitGroupRolesAssigned(unitToken)
    if issecretvalue(role) then return nil end
    return role
end

-- Thorns Only on Tank: the group's tanks, or the player while solo or in a
-- group without one.
local function ThornsHere(cfg, unitToken)
    if not cfg.missingBuffsThornsTank then return true end
    if groupTank then return RoleOf(unitToken) == "TANK" end
    return UnitIsUnit(unitToken, "player")
end

-- Salvation: every group member but a tank (no role assigned counts as not a
-- tank, as for the blessings; a secret role reads unknown: no icon). Never
-- solo, where threat is no one else's.
local function SalvationHere(unitToken)
    if solo then return false end
    local role = RoleOf(unitToken)
    return role ~= nil and role ~= "TANK"
end

-- Solo or not, and whether a group member has the tank role (one roster
-- walk per full pass).
local TOKENS
local function ScanTank()
    groupTank = false
    solo = not IsInGroup()
    if solo then return end
    for t = 1, #TOKENS do
        local u = TOKENS[t]
        if UnitExists(u) and RoleOf(u) == "TANK" then
            groupTank = true
            return
        end
    end
end

-- The blessing icon a member shows (a family index) or nil. None once the
-- member has a blessing of the player's (a paladin keeps one per target) or
-- while that is unknown. Otherwise: solo, Kings on the player whatever the
-- role (one reminder, no role picks); in a group, the first blessing of their
-- role's priority list (no role assigned: the DPS list, since many groups
-- never assign roles) that the player can cast and the member lacks, so one
-- another paladin gave moves the pick down the list (one the player cannot
-- cast is skipped; one the member reads unknown for stops the walk).
local function MissingBlessing(s, st, unitToken)
    if st.mine ~= false then return nil end
    if solo then
        if provider.kings and st.kings == false and UnitIsUnit(unitToken, "player") then
            return BLESS_INDEX.kings
        end
        return nil
    end
    local role = RoleOf(unitToken)
    if not role then return nil end
    if not BLESS_KEY[role] then role = "DAMAGER" end
    local _, class = UnitClass(unitToken)
    if issecretvalue(class) then class = nil end
    local wanted = Choice(s, role, class)
    for wid = 1, #wanted do
        local key = wanted[wid]
        local index = BLESS_INDEX[key]
        if index and provider[key] then
            local has = st[key]
            if has == nil then return nil end
            if has == false then return index end
        end
    end
    return nil
end

-------------------------------------------------------------------------------
--  Reading a member
-------------------------------------------------------------------------------
-- Whether the buff serves the member's class (no list = everyone); a class
-- the game keeps secret reads as unknown, so no icon.
local function Serves(fam, unitToken)
    local only = fam.only
    if not only then return true end
    local _, class = UnitClass(unitToken)
    if issecretvalue(class) then return false end
    return only[class] == true
end

local function Evaluate(unitToken, restricted)
    local st = status[unitToken]
    if not st then
        st = {}
        status[unitToken] = st
    end
    local found = instance[unitToken]
    if found then
        wipe(found)
    else
        found = {}
        instance[unitToken] = found
    end
    local known = UnitExists(unitToken) and UnitIsConnected(unitToken) and UnitIsVisible(unitToken)
    -- st.mine: the member has a blessing the player cast (a paladin keeps one
    -- blessing per target, so theirs is then done); nil while unknown.
    local mine = false
    for index = 1, NUM_FAMILIES do
        local key = FAMILIES[index].key
        local value
        -- A buff the player cannot cast, switched off everywhere, or one the
        -- member's class does not need, is never looked up (it never shows).
        if
            known
            and Tracked(index)
            and not (restricted and not Trusted(index))
            and Serves(FAMILIES[index], unitToken)
        then
            local entries = FamilyNames(index)
            if #entries > 0 then
                value = false
                for num = 1, #entries do
                    local success, aura =
                        pcall(C_UnitAuras.GetAuraDataBySpellName, unitToken, entries[num], "HELPFUL")
                    if not success or issecretvalue(aura) then
                        value = nil
                        break
                    end
                    if aura then
                        value = true
                        -- The caster, not isFromPlayerOrPlayerPet: that is
                        -- true for any player's aura, another paladin's too.
                        if FAMILIES[index].blessing and mine ~= true then
                            local source = aura.sourceUnit
                            if issecretvalue(source) then
                                mine = nil
                            elseif source == "player" then
                                mine = true
                            end
                        end
                        local iid = aura.auraInstanceID
                        if iid and not issecretvalue(iid) then found[iid] = true end
                        break
                    end
                end
            end
        end
        st[key] = value
        if value == nil and mine == false and FAMILIES[index].blessing and Tracked(index) then mine = nil end
    end
    st.mine = mine
end

-- A buff counts only while the player can cast it: their class casts it and
-- a trained rank (or the group version) is in their spellbook. Divine Spirit
-- is a talent, so a priest without it gets no Spirit icons.
local function Knows(fam)
    if fam.class ~= PLAYER_CLASS then return false end
    local ranks = fam.ranks
    for region = 1, #ranks do
        if C_SpellBook.IsSpellKnown(ranks[region]) then return true end
    end
    return false
end

-- Re-reads what the player can cast; true when any buff changed.
local function ScanProviders()
    local changed, anyBless = false, false
    for index = 1, NUM_FAMILIES do
        local fam = FAMILIES[index]
        local can = Knows(fam)
        if (provider[fam.key] == true) ~= can then
            provider[fam.key] = can
            changed = true
        end
        if can and fam.blessing then anyBless = true end
    end
    blessCaster = anyBless
    return changed
end

-------------------------------------------------------------------------------
--  Overlay
-------------------------------------------------------------------------------
local function Overlay(owner, level)
    local o = CreateFrame("Frame", nil, owner)
    o:SetFrameLevel(level)
    o:EnableMouse(false)
    o.slots = {}
    for index = 1, NUM_FAMILIES do
        local backdrop = o:CreateTexture(nil, "ARTWORK", nil, 0)
        backdrop:SetColorTexture(0, 0, 0, 1)
        local texture = o:CreateTexture(nil, "ARTWORK", nil, 1)
        texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        backdrop:Hide()
        texture:Hide()
        o.slots[index] = { bg = backdrop, tex = texture }
    end
    o:Hide()
    return o
end

-- The icons' glow (prefix keys missingBuffsGlow*, style 0 = none): one host
-- per shown icon. Every icon that goes, and every overlay that hides, stops
-- its glow, so nothing hidden stays in the shared glow driver.
local glowSpec = {}
local NO_SHAPE = { [4] = true } -- Shape Glow follows an icon shape; these cells have none

local function StopGlows(o, from)
    for index = from, NUM_FAMILIES do
        local g = o.slots[index].glow
        if g and g.fvOn then
            CUI.Glows.StopGlow(g)
            g.fvOn = nil
        end
    end
end

local function HideOverlay(o)
    StopGlows(o, 1)
    o:Hide()
end

local function ApplyGlows(o, s, num, size)
    local G = CUI.Glows
    local specInfo = G.SpecFromPrefix(glowSpec, s, "missingBuffsGlow")
    if not specInfo then
        StopGlows(o, 1)
        return
    end
    specInfo.excludes = NO_SHAPE
    for index = 1, num do
        local slot = o.slots[index]
        local g = slot.glow
        if not g then
            g = CreateFrame("Frame", nil, o)
            g:SetAllPoints(slot.bg)
            g:SetFrameLevel(o:GetFrameLevel() + 2)
            g:EnableMouse(false)
            slot.glow = g
        end
        G.StartSpecGlow(g, specInfo, size, size, "icon")
        g.fvOn = true
    end
    StopGlows(o, num + 1)
end

-- Lays out n icons (the family indices in list) at the configured position:
-- the overlay is exactly as wide as its icons, so a right-side position grows
-- leftward and a centred one stays centred. Same 9-point spots and edge inset
-- as the raid marker.
local function Layout(o, cfg, health, entries, num)
    local snap = mod.PixelSnap or function(val) return val end
    local size = snap(cfg.missingBuffsSize or 22)
    -- One physical pixel: the icon edge and the gap between icons.
    local edge = snap(1)
    if edge <= 0 then edge = 1 end
    for index = 1, NUM_FAMILIES do
        local slot = o.slots[index]
        if index <= num then
            local posX = (index - 1) * (size + edge)
            slot.bg:ClearAllPoints()
            slot.bg:SetPoint("TOPLEFT", o, "TOPLEFT", posX, 0)
            slot.bg:SetSize(size, size)
            slot.tex:ClearAllPoints()
            slot.tex:SetPoint("TOPLEFT", slot.bg, "TOPLEFT", edge, -edge)
            slot.tex:SetPoint("BOTTOMRIGHT", slot.bg, "BOTTOMRIGHT", -edge, edge)
            slot.tex:SetTexture(FamilyIcon(entries[index]))
            slot.bg:Show()
            slot.tex:Show()
        else
            slot.bg:Hide()
            slot.tex:Hide()
        end
    end
    if num == 0 then
        HideOverlay(o)
        return
    end
    o:SetSize(num * size + (num - 1) * edge, size)
    local owner = mod.RF_AnchorHost(health, cfg)
    local place = cfg.missingBuffsPosition or "top"
    local ox, oy = cfg.missingBuffsOffsetX or 0, cfg.missingBuffsOffsetY or 0
    o:ClearAllPoints()
    if place == "topleft" then
        o:SetPoint("TOPLEFT", owner, "TOPLEFT", 2 + ox, -2 + oy)
    elseif place == "top" then
        o:SetPoint("TOP", owner, "TOP", ox, -2 + oy)
    elseif place == "topright" then
        o:SetPoint("TOPRIGHT", owner, "TOPRIGHT", -2 + ox, -2 + oy)
    elseif place == "left" then
        o:SetPoint("LEFT", owner, "LEFT", 2 + ox, oy)
    elseif place == "right" then
        o:SetPoint("RIGHT", owner, "RIGHT", -2 + ox, oy)
    elseif place == "bottomleft" then
        o:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", 2 + ox, 2 + oy)
    elseif place == "bottom" then
        o:SetPoint("BOTTOM", owner, "BOTTOM", ox, 2 + oy)
    elseif place == "bottomright" then
        o:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", -2 + ox, 2 + oy)
    else
        o:SetPoint("CENTER", owner, "CENTER", ox, oy)
    end
    ApplyGlows(o, cfg, num, size)
    o:Show()
end

local paintList = {}
local function PaintMissing(button, skinData)
    if not skinData.health then return end
    local cfg = SettingsFor(skinData)
    local on = enabled and cfg and cfg.showMissingBuffs ~= false
    local o = skinData.fvMissing
    if not on then
        if o then HideOverlay(o) end
        return
    end
    local unitToken = button:GetAttribute("unit")
    local st = unitToken and status[unitToken]
    local num = 0
    if st then
        for index = 1, NUM_FAMILIES do
            local fam = FAMILIES[index]
            local key = fam.key
            -- This frame kind's own switch decides, so a buff turned off for
            -- party but on for raid shows on raid frames only.
            if
                not fam.blessing
                and st[key] == false
                and provider[key]
                and FamOn(cfg, fam)
                and (not fam.tankOnly or ThornsHere(cfg, unitToken))
                and (not fam.notTank or SalvationHere(unitToken))
            then
                num = num + 1
                paintList[num] = index
            end
        end
        -- One blessing at most, last: the member's role picks it.
        if blessCaster and BlessingsOn(cfg) then
            local bi = MissingBlessing(cfg, st, unitToken)
            if bi then
                num = num + 1
                paintList[num] = bi
            end
        end
    end
    if num == 0 and not o then return end
    if not o then
        o = Overlay(button, button:GetFrameLevel() + mod.LVL_MARKER)
        skinData.fvMissing = o
    end
    Layout(o, cfg, skinData.health, paintList, num)
end

local function PaintUnit(unitToken)
    local GetFFD = mod.GetFFD
    local b = mod._raidUnitToButton and mod._raidUnitToButton[unitToken]
    if b then PaintMissing(b, GetFFD(b)) end
    b = mod._partyUnitToButton and mod._partyUnitToButton[unitToken]
    if b then PaintMissing(b, GetFFD(b)) end
    b = mod._xfUnitToButton and mod._xfUnitToButton[unitToken]
    if b then PaintMissing(b, GetFFD(b)) end
end

local function PaintList(entries)
    if not entries then return end
    local GetFFD = mod.GetFFD
    for index = 1, #entries do
        local b = entries[index]
        PaintMissing(b, GetFFD(b))
    end
end

local function PaintAll()
    PaintList(mod._allButtons) -- raid + Extra Frames
    PaintList(mod._partyAllButtons)
end

local function Mapped(unitToken)
    return (mod._raidUnitToButton and mod._raidUnitToButton[unitToken])
        or (mod._partyUnitToButton and mod._partyUnitToButton[unitToken])
        or (mod._xfUnitToButton and mod._xfUnitToButton[unitToken])
end

-------------------------------------------------------------------------------
--  Passes (one per frame)
-------------------------------------------------------------------------------
-- dirty: members to look up again; pendingBtns: buttons that took a new unit
-- (painted directly: the unit maps may not have caught up with them yet).
local dirty, pendingBtns, flushArmed, fullArmed = {}, {}, false, false

-- Full pass: every button's own unit, read off the button itself.
local function EvaluateList(entries, restricted)
    if not entries then return end
    for index = 1, #entries do
        local unitToken = entries[index]:GetAttribute("unit")
        if unitToken and not status[unitToken] then Evaluate(unitToken, restricted) end
    end
end

local function Flush()
    flushArmed = false
    if not enabled then
        wipe(dirty)
        wipe(pendingBtns)
        fullArmed = false
        return
    end
    local restricted = CUI.AuraKit.AurasRestricted()
    local full = fullArmed
    fullArmed = false
    if full then
        wipe(dirty)
        wipe(pendingBtns)
        ScanProviders()
        ScanTank()
        wipe(status)
        wipe(instance)
        EvaluateList(mod._allButtons, restricted)
        EvaluateList(mod._partyAllButtons, restricted)
        PaintAll()
        return
    end
    for unitToken in pairs(dirty) do
        Evaluate(unitToken, restricted)
    end
    for unitToken in pairs(dirty) do
        PaintUnit(unitToken)
    end
    local GetFFD = mod.GetFFD
    for btn in pairs(pendingBtns) do
        PaintMissing(btn, GetFFD(btn))
    end
    wipe(dirty)
    wipe(pendingBtns)
end

local function Arm()
    if flushArmed then return end
    flushArmed = true
    C_Timer.After(0, Flush)
end

local function MarkDirty(unitToken)
    dirty[unitToken] = true
    Arm()
end

local function ArmFull()
    fullArmed = true
    Arm()
end

-------------------------------------------------------------------------------
--  Events (registered only while the indicator is on somewhere)
-------------------------------------------------------------------------------
-- The payload is secret while auras are restricted (UNIT_AURA is
-- SecretWhenAurasRestricted): nothing in it can be read, so the member is
-- looked up again, but only while a buff the player provides stays readable
-- under the restriction. The rest read unknown until it lifts, and the
-- restriction edge re-reads everyone then.
local function Unprobeable(unitToken)
    for index = 1, NUM_FAMILIES do
        if Tracked(index) and Trusted(index) then
            MarkDirty(unitToken)
            return
        end
    end
end

-- Probe the payload first: only an added or removed Missing Buffs aura
-- sends the member back for a look-up; a full update always does.
local function OnUnitAura(unitToken, details)
    if not Mapped(unitToken) then return end
    if not details then
        MarkDirty(unitToken)
        return
    end
    if issecretvalue(details) then
        Unprobeable(unitToken)
        return
    end
    local full = details.isFullUpdate
    if issecretvalue(full) then
        Unprobeable(unitToken)
        return
    end
    if full then
        MarkDirty(unitToken)
        return
    end
    local added = details.addedAuras
    if added then
        if issecretvalue(added) then
            Unprobeable(unitToken)
            return
        end
        for index = 1, #added do
            local aura = added[index]
            if issecretvalue(aura) then
                Unprobeable(unitToken)
                return
            end
            local spellRef = aura.spellId
            if issecretvalue(spellRef) then
                Unprobeable(unitToken)
                return
            end
            local fi = spellRef and FAMILY_BY_ID[spellRef]
            if fi and Tracked(fi) then
                MarkDirty(unitToken)
                return
            end
        end
    end
    local removed, found = details.removedAuraInstanceIDs, instance[unitToken]
    if removed and found and next(found) then
        if issecretvalue(removed) then
            Unprobeable(unitToken)
            return
        end
        for index = 1, #removed do
            local iid = removed[index]
            if issecretvalue(iid) then
                Unprobeable(unitToken)
                return
            end
            if found[iid] then
                MarkDirty(unitToken)
                return
            end
        end
    end
end

local function OnTrackerEvent(_, evt, unitToken, details)
    if evt == "UNIT_AURA" then
        OnUnitAura(unitToken, details)
    elseif Mapped(unitToken) then
        MarkDirty(unitToken)
    end
end

-- RegisterUnitEvent takes two units: the 45 group tokens ride 23 frames
-- (built here, so their events bill this module; registered only while on).
-- ScanTank walks the same list (declared above it).
TOKENS = { "player" }
for index = 1, 4 do
    TOKENS[#TOKENS + 1] = "party" .. index
end
for index = 1, 40 do
    TOKENS[#TOKENS + 1] = "raid" .. index
end
local trackers = {}
for index = 1, #TOKENS, 2 do
    local frame = CreateFrame("Frame")
    frame._u1, frame._u2 = TOKENS[index], TOKENS[index + 1]
    frame:SetScript("OnEvent", OnTrackerEvent)
    trackers[#trackers + 1] = frame
end

local CHAT_RESTRICTION = Enum.AddOnRestrictionType and Enum.AddOnRestrictionType.Chat

local world = CreateFrame("Frame")
world:SetScript("OnEvent", function(_, evt, rtype)
    if evt == "SPELLS_CHANGED" then
        -- A buff learned or lost (a rank trained, the Divine Spirit talent
        -- taken or dropped) re-reads everyone; anything else costs one scan.
        if ScanProviders() then ArmFull() end
    elseif evt == "ADDON_RESTRICTION_STATE_CHANGED" then
        -- A restriction starting or lifting changes which buffs can be read.
        -- The pass runs next frame, after the activation dispatch, so it reads
        -- the settled state; addon chat restrictions never touch auras.
        if rtype ~= CHAT_RESTRICTION then ArmFull() end
    else
        ArmFull()
    end
end)

local function SetEvents(on)
    for index = 1, #trackers do
        local frame = trackers[index]
        if on then
            frame:RegisterUnitEvent("UNIT_AURA", frame._u1, frame._u2)
            frame:RegisterUnitEvent("UNIT_CONNECTION", frame._u1, frame._u2)
        else
            frame:UnregisterAllEvents()
        end
    end
    if on then
        world:RegisterEvent("GROUP_ROSTER_UPDATE")
        -- Roles pick the blessing and the tank-only Thorns.
        world:RegisterEvent("PLAYER_ROLES_ASSIGNED")
        world:RegisterEvent("PLAYER_ENTERING_WORLD")
        -- Every aura restriction edge (combat, encounters, instances).
        world:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
        -- What the player can cast (only a priest, druid or paladin gets here).
        world:RegisterEvent("SPELLS_CHANGED")
    else
        world:UnregisterAllEvents()
    end
end

-- Settles which buffs matter: a buff counts while its switch is on in a
-- raid, party or Extra Frames settings table whose indicator is on. Returns
-- whether any buff of the player's class counts (the indicator is on at
-- all), and whether any buff's answer changed.
local SETTINGS = {} -- scratch: this pass's three settings tables
local function ScanWanted()
    SETTINGS[1], SETTINGS[2], SETTINGS[3] = mod._scaledProfile, mod._scaledPartyProxy, mod._scaledExtraProxy
    local any, changed = false, false
    for index = 1, NUM_FAMILIES do
        local fam = FAMILIES[index]
        local on = false
        for t = 1, 3 do
            local cfg = SETTINGS[t]
            if cfg and cfg.showMissingBuffs ~= false and FamOn(cfg, fam) then
                on = true
                break
            end
        end
        if on and fam.class == PLAYER_CLASS then any = true end
        if (wantFam[fam.key] == true) ~= on then
            wantFam[fam.key] = on
            changed = true
        end
    end
    return any, changed
end

-- On (for a class that casts one of the buffs at all): events and a full
-- look-up; a buff switched on or off while on re-reads everyone for it.
local syncArmed = false
local function Sync()
    syncArmed = false
    local wanted, changed = false, false
    if CAN_EVER then
        wanted, changed = ScanWanted()
    end
    if wanted ~= enabled then
        enabled = wanted
        SetEvents(wanted)
        if wanted then
            ArmFull()
        else
            wipe(status)
            wipe(instance)
            wipe(dirty)
            wipe(pendingBtns)
            PaintAll()
        end
    elseif wanted and changed then
        ArmFull()
    end
end

-------------------------------------------------------------------------------
--  Main-file hooks
-------------------------------------------------------------------------------
-- Each reload path, per button: re-lay the icons from what is known (no
-- look-ups), then settle the on/off state once for the whole pass.
function mod.RF_FvMissingAnchor(button, skinData)
    PaintMissing(button, skinData)
    if not syncArmed then
        syncArmed = true
        C_Timer.After(0, Sync)
    end
end

-- The secure header's unit assignment (every roster re-process, same unit
-- included): only a button whose unit really changed looks its member up.
function mod.RF_FvMissingUnit(button, skinData, unitToken)
    if not enabled or skinData._fvUnit == unitToken then return end
    skinData._fvUnit = unitToken
    if not unitToken then
        -- An emptied button hides: its glows leave the driver with it.
        if skinData.fvMissing then HideOverlay(skinData.fvMissing) end
        return
    end
    pendingBtns[button] = true
    MarkDirty(unitToken)
end

-- Options preview: a fixed spread of missing buffs while the indicators
-- preview (the Indicators eye) is on, minus the buffs switched off. "B" is
-- the blessing slot: the top pick of the first role with any (DPS first).
local PREVIEW = {
    [2] = { 1 },
    [4] = { 1, 2 },
    [7] = { 3, "B" },
    [9] = { 1, 2, 3, 4, 5, "B" },
    [12] = { 2, 4 },
    [15] = { 1, 3, 5 },
    [18] = { 4, "B" },
}
local PREVIEW_ROLES = { "DAMAGER", "HEALER", "TANK" }
local function PreviewBlessing(s)
    for region = 1, #PREVIEW_ROLES do
        local c = Choice(s, PREVIEW_ROLES[region])
        for wid = 1, #c do
            local index = BLESS_INDEX[c[wid]]
            if index then return index end
        end
    end
end
local previewList = {}
function mod.RF_FvMissingPreview(frame, index, cfg, indVis)
    local spread = indVis and cfg.showMissingBuffs ~= false and frame._health and PREVIEW[index]
    local num = 0
    if spread then
        for k = 1, #spread do
            local index = spread[k]
            if index == "B" then index = PreviewBlessing(cfg) end
            if index and (FAMILIES[index].blessing or FamOn(cfg, FAMILIES[index])) then
                num = num + 1
                previewList[num] = index
            end
        end
    end
    local o = frame._fvMissing
    if num == 0 then
        if o then HideOverlay(o) end
        return
    end
    if not o then
        o = Overlay(frame, frame:GetFrameLevel() + mod.LVL_MARKER)
        frame._fvMissing = o
    end
    Layout(o, cfg, frame._health, previewList, num)
end

-- First look once the world is up (the reload paths may not run at login).
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Sync()
end)
