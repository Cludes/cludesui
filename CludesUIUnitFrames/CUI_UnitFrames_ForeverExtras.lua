if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_UnitFrames_ForeverExtras.lua
--
--  WoW Forever extras on the unit frames: the pet happiness icon beside the
--  pet frame and the combo point arc round the target or player portrait.
--  Both apply functions return at once off WoW Forever. Reads the main file
--  through ns and ns._internals; db is set through I.dbSetters.
-------------------------------------------------------------------------------
local _, mod = ...

local issecretvalue = issecretvalue

local Inner = mod._internals
local frameList = Inner.frames
local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(val)
    saved = val
end

-- Pet happiness (WoW Forever): the stock pet frame's mood icon, carried
-- beside our pet frame under Blizzard's own rule -- shown only for a hunter
-- pet whose happiness reads 1..3, with that state's atlas. The icon frame is
-- also the event receiver; it is built the first time the feature is on for
-- a hunter and drops every event while off, so it costs nothing otherwise.
function mod.UF_RefreshPetHappiness(hgt)
    local happiness = C_PetInfo.GetPetHappiness()
    local _, isHunterPet = HasPetUI()
    local atlas = isHunterPet
            and ((happiness == 1 and "UI-PetMad") or (happiness == 2 and "UI-PetNeutral") or (happiness == 3 and "UI-PetHappiness"))
        or nil
    if atlas then
        -- Paint only a real mood change (the texture is set nowhere else).
        if hgt._atlas ~= atlas then
            hgt._atlas = atlas
            hgt._tex:SetAtlas(atlas)
        end
        hgt:Show()
    else
        hgt:Hide()
    end
end

-- Hover text, read fresh: state, damage share, loyalty trend and diet.
function mod.UF_PetHappinessOnEnter(self)
    -- Faded out with its frame (the pet mirrors the player frame's alpha and
    -- mouseover mode rests at 0): an unseen icon shows no tooltip. An alpha the
    -- client withholds (secret, or no value at all when it refuses alpha
    -- access) shows it, as on a visible icon.
    local a = self:GetEffectiveAlpha()
    if type(a) == "number" and not issecretvalue(a) and a < 0.05 then
        return
    end
    local happiness, dmg, loyalty = C_PetInfo.GetPetHappiness()
    local textValue = (happiness == 1 and PET_HAPPINESS1)
        or (happiness == 2 and PET_HAPPINESS2)
        or (happiness == 3 and PET_HAPPINESS3)
    if not textValue then
        return
    end
    if dmg then
        textValue = textValue .. "\n" .. PET_DAMAGE_PERCENTAGE:format(dmg)
    end
    if loyalty and loyalty < 0 then
        textValue = textValue .. "\n" .. LOSING_LOYALTY
    elseif loyalty and loyalty > 0 then
        textValue = textValue .. "\n" .. GAINING_LOYALTY
    end
    local diet = C_PetInfo.GetPetFoodTypes()
    if diet and #diet > 0 then
        textValue = textValue .. "\n" .. PET_DIET_TEMPLATE:format(table.concat(diet, PET_FOOD_DELIMIT))
    end
    CludesUI.ShowWidgetTooltip(self, textValue)
end

function mod.UF_PetHappinessOnLeave()
    CludesUI.HideWidgetTooltip()
end

-- Settings apply: builds the icon on first use, re-seats size, side and
-- offsets, and arms or drops its events. Every reload pass runs it (the
-- options setters reach it through ReloadAndUpdate) and it is safe to call
-- directly; it returns at once off WoW Forever.
function mod.UF_ApplyPetHappiness()
    if CludesUI.IS_FOREVER ~= true then
        return
    end
    local popFrame = frameList.pet
    local cfg = saved.profile.pet
    local hgt = popFrame and popFrame._petHappy
    -- Only hunter pets carry happiness: every other class never builds it.
    local enabled = popFrame
        and cfg
        and cfg.happinessEnabled ~= false
        and not mod.VisUnitDisabled(saved.profile, "pet")
        and select(2, UnitClass("player")) == "HUNTER"
    if not enabled then
        if hgt then
            hgt:UnregisterAllEvents()
            hgt:Hide()
        end
        return
    end
    if not hgt then
        hgt = CreateFrame("Frame", nil, popFrame)
        -- Hover only: clicks fall through to the unit button underneath.
        hgt:EnableMouseMotion(true)
        hgt._tex = hgt:CreateTexture(nil, "OVERLAY")
        hgt._tex:SetAllPoints()
        hgt:SetScript("OnEvent", mod.UF_RefreshPetHappiness)
        hgt:SetScript("OnEnter", mod.UF_PetHappinessOnEnter)
        hgt:SetScript("OnLeave", mod.UF_PetHappinessOnLeave)
        hgt:Hide()
        popFrame._petHappy = hgt
    end
    local sz = cfg.happinessSize or 20
    local align = cfg.happinessAlign or "right"
    local posX, posY = cfg.happinessX or 0, cfg.happinessY or 0
    hgt:SetSize(sz, sz)
    hgt:ClearAllPoints()
    if align == "left" then
        hgt:SetPoint("RIGHT", popFrame, "LEFT", posX, posY)
    elseif align == "top" then
        hgt:SetPoint("BOTTOM", popFrame, "TOP", posX, posY)
    else
        hgt:SetPoint("LEFT", popFrame, "RIGHT", posX, posY)
    end
    -- Above the border and the name/health text (the strata pass re-stacks).
    if popFrame._textOverlay then
        hgt:SetFrameLevel(popFrame._textOverlay:GetFrameLevel() + 5)
    end
    hgt:RegisterUnitEvent("UNIT_HAPPINESS", "pet")
    hgt:RegisterUnitEvent("UNIT_PET", "player")
    -- The pet's state may not read yet at login: the zone-in edge repaints.
    hgt:RegisterEvent("PLAYER_ENTERING_WORLD")
    mod.UF_RefreshPetHappiness(hgt)
end

-- Combo point arc (WoW Forever style): the stock target frame's combo points,
-- the vanilla pip file plotted in an arc round a portrait, drawn as the
-- "Blizzard" class resource under that look (Forever has no other class
-- resource display). Combo Points (player.foreverComboLocation) puts it
-- round the target portrait (the stock spot), round the player portrait, or
-- nowhere. Built once for a rogue or druid and moved to whichever of our two
-- frames hosts it; its events arrive through one receiver born in this main
-- chunk (so they bill to this module), which drops every event while the arc
-- is off, so it costs nothing otherwise. The count can read secret, so
-- visibility never compares it in Lua: each pip rides a one-point StatusBar
-- gate (SetMinMaxValues(i-1, i) + SetValue does the compare C-side) whose
-- mask, pinned to the fill's right edge, bounds the pip's textures, and a
-- one-point gate over the whole arc hides it while empty. A plain count also
-- plays the stock fill flash.
mod.UF_COMBO_FILE = "Interface\\ComboFrame\\ComboPoint"
-- Each slot's TOPRIGHT from the target box's TOPRIGHT (the stock container
-- offset folded in); slots 7-9 are the extra points, at 0.6 alpha.
mod.UF_COMBO_SLOTS = {
    { -63, -6 },
    { -50.5, -5 },
    { -38, -6 },
    { -26.5, -11.5 },
    { -17.5, -20 },
    { -12, -31.5 },
    { -10, -43 },
    { -12, -54 },
    { 0, -46 },
}
-- A w x h gate and its mask: the mask is the gate's size and rides the fill's
-- right edge, so an empty fill parks it a full width clear of the payload.
function mod.UF_ComboGate(hostFrame, wid, hgt)
    local g = CreateFrame("StatusBar", nil, hostFrame)
    g:SetSize(wid, hgt)
    g:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    local fillTex = g:GetStatusBarTexture()
    fillTex:SetAlpha(0)
    g:SetMinMaxValues(0, 1)
    g:SetValue(0)
    local m = g:CreateMaskTexture()
    m:SetTexture("Interface\\Buttons\\WHITE8x8", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
    m:SetSize(wid, hgt)
    m:SetPoint("RIGHT", fillTex, "RIGHT", 0, 0)
    return g, m
end
function mod.UF_BuildComboArc(owner)
    local arc = CreateFrame("Frame", nil, owner)
    -- Spans every slot's textures (the arc gate's payload).
    arc:SetSize(82, 72)
    arc._gate, arc._mask = mod.UF_ComboGate(arc, 82, 72)
    arc._gate:SetPoint("TOPLEFT", arc, "TOPLEFT", 0, 0)
    local file = mod.UF_COMBO_FILE
    local pips, gates = {}, {}
    for key = 1, 9 do
        local pip = CreateFrame("Frame", nil, arc)
        pip:SetSize(12, 12)
        if key >= 7 then
            pip:SetAlpha(0.6)
        end
        local base = pip:CreateTexture(nil, "BACKGROUND")
        base:SetTexture(file)
        base:SetTexCoord(0, 0.375, 0, 1)
        base:SetSize(12, 16)
        base:SetPoint("TOPLEFT", pip, "TOPLEFT", 0, 0)
        local highlight = pip:CreateTexture(nil, "ARTWORK")
        highlight:SetTexture(file)
        highlight:SetTexCoord(0.375, 0.5625, 0, 1)
        highlight:SetSize(8, 16)
        highlight:SetPoint("TOPLEFT", pip, "TOPLEFT", 2, 0)
        highlight:SetAlpha(0)
        local shine = pip:CreateTexture(nil, "OVERLAY")
        shine:SetTexture(file)
        shine:SetTexCoord(0.5625, 1, 0, 1)
        shine:SetSize(14, 16)
        shine:SetPoint("TOPLEFT", pip, "TOPLEFT", 0, 4)
        shine:SetBlendMode("ADD")
        shine:SetAlpha(0)
        -- The pip's own gate spans its three textures (the shine rides 4 up).
        local g, m = mod.UF_ComboGate(pip, 14, 20)
        g:SetPoint("TOPLEFT", pip, "TOPLEFT", 0, 4)
        highlight:AddMaskTexture(m)
        shine:AddMaskTexture(m)
        -- A newly filled point: the highlight fades in, then the shine flashes.
        local ag = pip:CreateAnimationGroup()
        ag:SetToFinalAlpha(true)
        local a = ag:CreateAnimation("Alpha")
        a:SetTarget(highlight)
        a:SetFromAlpha(0)
        a:SetToAlpha(1)
        a:SetDuration(0.4)
        a:SetOrder(1)
        a = ag:CreateAnimation("Alpha")
        a:SetTarget(shine)
        a:SetFromAlpha(0)
        a:SetToAlpha(1)
        a:SetDuration(0.3)
        a:SetOrder(2)
        a = ag:CreateAnimation("Alpha")
        a:SetTarget(shine)
        a:SetFromAlpha(1)
        a:SetToAlpha(0)
        a:SetDuration(0.4)
        a:SetOrder(3)
        pip._base, pip._hl, pip._shine, pip._mask, pip._anim = base, highlight, shine, m, ag
        pips[key], gates[key] = pip, g
    end
    arc._pips, arc._gates = pips, gates
    -- The arc fades in when its first point lands.
    local fade = arc:CreateAnimationGroup()
    fade:SetToFinalAlpha(true)
    local fa = fade:CreateAnimation("Alpha")
    fa:SetFromAlpha(0)
    fa:SetToAlpha(1)
    fa:SetDuration(0.3)
    arc._fade = fade
    mod._ufComboArc = arc
    return arc
end
-- The arc's event receiver (the Forever client only; armed by
-- ns.UF_ApplyForeverComboArc).
if CludesUI.IS_FOREVER == true then
    mod._ufComboEv = CreateFrame("Frame")
    mod._ufComboEv:SetScript("OnEvent", function(_, ...)
        local arc = mod._ufComboArc
        if arc then
            mod.UF_ComboArcRefresh(arc, ...)
        end
    end)
end
-- The classes the arc draws for (combo points on WoW Forever).
function mod.UF_ComboClass()
    local _, classTok = UnitClass("player")
    return classTok == "ROGUE" or classTok == "DRUID"
end
-- Combo Points: "target" (the stock spot; anything unknown reads as it),
-- "player" or "never".
function mod.UF_ComboLocation()
    local cfg = saved and saved.profile and saved.profile.player
    local val = cfg and cfg.foreverComboLocation
    if val == "player" or val == "never" then
        return val
    end
    return "target"
end
-- The slots ring the stock target portrait (58 wide at TOPRIGHT -26,-19, its
-- centre -55,-48 off the box's top right). A host on another kit's ring (the
-- player's 60 at TOPLEFT 24,-19) moves every slot by the gap between the two
-- centres, in the slots' own frame before the mirror; 0,0 on the target kit.
function mod.UF_ComboRingShift(G)
    local P = G and G.portrait
    if not (P and P.size) then
        return 0, 0
    end
    local region = P.size / 2
    local cx = (P.point == "TOPLEFT") and -(P.x + region) or (P.x - region)
    return cx + 55, P.y - region + 48
end
-- Which slots the arc uses (from the point cap, as the stock frame lays it
-- out) and which empty pips show with the arc; re-run only on a cap or
-- colourblind change. A secret cap keeps the last layout.
function mod.UF_ComboArcLayout(arc)
    local mx = UnitPowerMax("player", Enum.PowerType.ComboPoints)
    if issecretvalue(mx) then
        if arc._max then
            return
        end
        mx = 5
    end
    if not mx or mx <= 0 then
        mx = 5
    end
    local callback = C_CVar.GetCVarBool("colorblindMode") and true or false
    if arc._max == mx and arc._cb == callback then
        return
    end
    -- A cap of 6 or 9 starts on the first slot with six in the arc; any other
    -- starts one slot in with five. Points past those show only while filled.
    local start, extra = 2, 6
    if mx == 6 or mx == 9 then
        start, extra = 1, 7
    end
    arc._max, arc._start, arc._cb = mx, start, callback
    local pips, gates = arc._pips, arc._gates
    for key = 1, 9 do
        local pip = pips[key]
        local index = key - start + 1
        if index >= 1 and index <= mx then
            gates[key]:SetMinMaxValues(index - 1, index)
            -- The empty pip shows with the arc, or only while filled (the
            -- extra points; every point in colourblind mode).
            local wanted = (callback or index >= extra) and pip._mask or arc._mask
            if pip._baseMask ~= wanted then
                if pip._baseMask then
                    pip._base:RemoveMaskTexture(pip._baseMask)
                end
                pip._base:AddMaskTexture(wanted)
                pip._baseMask = wanted
            end
            pip:Show()
        else
            pip:Hide()
        end
    end
end
function mod.UF_ComboArcRefresh(arc, evt, _, powerType)
    if evt == "UNIT_POWER_UPDATE" and powerType ~= "COMBO_POINTS" then
        return
    end
    if arc._cb == nil or evt == "UNIT_MAXPOWER" or evt == "PLAYER_ENTERING_WORLD" then
        mod.UF_ComboArcLayout(arc)
    end
    -- The target's count (the stock frame's read: the power value lags a
    -- target swap). Fed to every gate as it comes, secret or not.
    local num = GetComboPoints("player", "target")
    arc._gate:SetValue(num)
    local gates, pips = arc._gates, arc._pips
    for key = 1, 9 do
        gates[key]:SetValue(num)
    end
    if issecretvalue(num) then
        -- No compare: the gates alone show the filled points, at full
        -- highlight, with no flash.
        if not arc._secret then
            arc._secret = true
            arc._fade:Stop()
            arc:SetAlpha(1)
            for key = 1, 9 do
                local pip = pips[key]
                pip._anim:Stop()
                pip._hl:SetAlpha(1)
                pip._shine:SetAlpha(0)
            end
        end
        return
    end
    -- Back from a secret stretch: settle on the count without replaying it.
    local last = arc._secret and num or (arc._last or 0)
    arc._secret = nil
    arc._last = num
    if num > 0 and last == 0 then
        arc._fade:Stop()
        arc._fade:Play()
    end
    local start = arc._start
    for index = 1, arc._max do
        local pip = pips[start + index - 1]
        if not pip then
            break
        end
        if index > num then
            pip._anim:Stop()
            pip._hl:SetAlpha(0)
            pip._shine:SetAlpha(0)
        elseif index > last then
            pip._anim:Stop()
            pip._hl:SetAlpha(0)
            pip._shine:SetAlpha(0)
            pip._anim:Play()
        end
    end
end
-- Settings apply: on only under the WoW Forever style with the "Blizzard"
-- class resource, for a rogue or druid; hosts the arc on the frame Combo
-- Points names (our target or player frame), builds it on first use, places
-- it round that frame's portrait (mirrored onto a portrait on the left) and
-- arms its events, else drops them. Blizzard's own combo points, kept beside
-- Blizzard's own target frame, stand down for any other spot. Every reload
-- pass, the class resource toggle and the Combo Points setter run it; it
-- returns at once off WoW Forever.
function mod.UF_ApplyForeverComboArc()
    if CludesUI.IS_FOREVER ~= true then
        return
    end
    local arc, ev = mod._ufComboArc, mod._ufComboEv
    local owner
    if mod.UF_Forever() and saved.profile.player.classPowerStyle == "blizzard" and mod.UF_ComboClass() then
        -- Combo Points belongs to our player frame: without one (its Frame
        -- Source Blizzard or Hidden) it reads as the stock spot, so nothing
        -- is taken down and no choice is stranded.
        local loc = frameList.player and mod.UF_ComboLocation() or "target"
        if loc == "target" then
            owner = frameList.target
        else
            if loc == "player" then
                owner = frameList.player
            end
            -- Blizzard's own goes to the hidden parent out of combat and
            -- outside Edit Mode (a skipped pass retries on the next one). The
            -- hidden parent is pinned for the session: only a reload brings
            -- it back (the options setters offer one).
            if mod._ufComboFrameKept then
                if InCombatLockdown() then
                    mod.CombatQueue.Defer("UF_ComboArc", mod.UF_ApplyForeverComboArc)
                elseif not (EditModeManagerFrame and EditModeManagerFrame:IsShown()) then
                    mod._ufComboFrameKept, mod._ufComboFrameByLoc = nil, true
                    mod.UF_HideBlizzardFrame(_G.ComboFrame)
                end
            end
        end
    end
    if not owner then
        ev:UnregisterAllEvents()
        if arc then
            arc:Hide()
        end
        return
    end
    arc = arc or mod.UF_BuildComboArc(owner)
    -- Re-seated only when the host, its kit or its side changed (Portrait
    -- Side swaps the kit).
    local G = mod.UF_BlizzGeom(owner)
    local mirror = (G and G.side == "left") or nil
    if arc._host ~= owner or arc._kit ~= G or arc._mirror ~= mirror then
        arc._host, arc._kit, arc._mirror = owner, G, mirror
        if arc:GetParent() ~= owner then
            arc:SetParent(owner)
        end
        local dx, dy = mod.UF_ComboRingShift(G)
        arc:ClearAllPoints()
        mod.UF_BlizzPoint(arc, "TOPRIGHT", owner, "TOPRIGHT", 4 + dx, dy, mirror)
        local slots, pips = mod.UF_COMBO_SLOTS, arc._pips
        for key = 1, 9 do
            pips[key]:ClearAllPoints()
            mod.UF_BlizzPoint(
                pips[key],
                "TOPRIGHT",
                owner,
                "TOPRIGHT",
                slots[key][1] + dx,
                slots[key][2] + dy,
                mirror
            )
        end
    end
    -- Over the art, portrait and bars, one level above the level host (its
    -- level and PvP badges), as Blizzard's own draws over its frame's badges.
    local clip = owner._barClip
    arc:SetFrameStrata((clip and clip:GetFrameStrata()) or owner:GetFrameStrata())
    arc:SetFrameLevel(((clip and clip:GetFrameLevel()) or owner:GetFrameLevel()) + 13)
    ev:RegisterEvent("PLAYER_TARGET_CHANGED")
    -- Points moving to a new target keep their count, so no power event fires.
    ev:RegisterEvent("COMBO_TARGET_CHANGED")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
    ev:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    -- Re-lays only on a cap or colourblind change (a colourblind change has
    -- no event of its own, so every apply asks).
    mod.UF_ComboArcLayout(arc)
    arc:Show()
    mod.UF_ComboArcRefresh(arc)
end
