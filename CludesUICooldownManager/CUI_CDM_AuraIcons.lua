if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_CDM_AuraIcons.lua
--
--  Aura icons of our own on cooldown and utility bars, for entries no
--  Blizzard frame draws. Each is an icon frame of ours, built once per bar and
--  entry and laid out, decorated, reparented and parked like a racial's (an
--  injected frame, _isPresetFrame), with one engine aura slot (AuraKit) inside
--  it: the slot shows while a matching aura is up, with the aura's own icon,
--  swipe and countdown in the bar's custom-aura look (_AC.BuildStyle), so it
--  works while aura data is hidden from addon code. Under it the frame shows
--  the entry's idle icon.
--
--  Two kinds of entry:
--    * a custom buff spell ID on a cooldown or utility bar (the Add Buff
--      menu's Custom Spell ID, stored as a hosted-buff marker): drawn here
--      while no Blizzard frame or placeholder claims it, its idle icon grey,
--      as a hosted buff keeps its slot on such a bar;
--    * a spell ID a provider draws (ns.CDM_AuraIconProvider): the WoW Forever
--      Seals stand-in (CUI_CDM_ForeverSeals.lua). The drop pass and the
--      repopulate keep such an ID, and the options preview never dims it as
--      unlearned (ns.CDM_AuraIconKeeps).
--
--  One slot per entry, moved between bars through its proxy: a frame of ours
--  the slot button fills, parented to the host frame, so the slot takes the
--  host's visibility, opacity and strata, and a hidden host hides the
--  container, which then registers no events. The slot is built again only
--  when its include set changes (engine buttons are never freed).
--
--  Reached from: CUI_CDM_HookReanchor.lua (Phase 3 injection, and the end of
--  every reanchor), CUI_CDM_Icons.lua (RefreshCDMIconAppearance), and the
--  drop pass, the repopulate and the options preview (ns.CDM_AuraIconKeeps).
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._hookInternals
if not Inner or Inner.broken or not Inner._AC then
    return
end
local _AC, _presetFrames = Inner._AC, Inner._presetFrames
local barDataByKey = mod.barDataByKey
local IsSecret = CludesUI.IsSecret

local AKWorker = CludesUI.AuraKit.NewBuildWorker()

-- The slot sits over the host's art, border and swipe (border +13/+14, swipe
-- +14), under its glows (+16) and text (+23), as DecorateFrame levels them.
local SLOT_LEVEL = 14

local entries = {} -- provider key -> entry
local placed = {} -- entries attached since the last post-reanchor pass
local byID = {} -- spell ID -> the provider that draws it
local pendingAliases = {} -- providers whose Aliases have not been read yet
local buffProviders = {} -- custom buff spell ID -> its provider
-- host frame -> the entry it holds (one frame per bar and entry)
local hostEntry = setmetatable({}, { __mode = "k" })

-------------------------------------------------------------------------------
--  Providers
--
--  provider = {
--    key,           unique entry key
--    tip,           the spell ID the idle frame's tooltip shows
--    Include(),     -> the aura spell IDs (a set, never empty) and a signature
--    Icon(),        -> the idle art
--    Desaturate(),  -> whether the idle art is grey
--    Off(),         optional: true once the entry stands down
--    Aliases(),     optional: more spell IDs it draws, read once Blizzard's
--                   cooldown data has loaded
--    Placed(),      optional: after each reanchor that placed it
--  }
-------------------------------------------------------------------------------
function mod.CDM_AuraIconProvider(spellId, provider)
    byID[spellId] = provider
    if provider.Aliases then
        pendingAliases[#pendingAliases + 1] = provider
    end
end

local function ReadAliases()
    if not mod._cdmDataLoaded then
        return
    end
    for index = #pendingAliases, 1, -1 do
        local p = table.remove(pendingAliases, index)
        local ids = p.Aliases()
        if ids then
            for jdx = 1, #ids do
                if byID[ids[jdx]] == nil then
                    byID[ids[jdx]] = p
                end
            end
        end
        -- What it read can widen the include set of an entry built earlier.
        local Rec = entries[p.key]
        if Rec then
            Rec.dirty = true
        end
    end
end

-- An assigned spell ID a provider draws: kept by the drop pass and the
-- repopulate, never dimmed as unlearned by the options preview.
function mod.CDM_AuraIconKeeps(ident)
    if pendingAliases[1] then
        ReadAliases()
    end
    return byID[ident] ~= nil
end

-------------------------------------------------------------------------------
--  The engine slot
-------------------------------------------------------------------------------
-- A learned spell can widen an include set (a WoW Forever rank) and a talent
-- change can move a spell's override: each set is read again at its next
-- placement. Registered only while an entry is placed.
local listening = false
local events = mod.TakeShell()
events:SetScript("OnEvent", function()
    for _, Rec in pairs(entries) do
        Rec.dirty = true
    end
    if mod.QueueReanchor then
        mod.QueueReanchor()
    end
end)

local function Listen(enabled)
    if enabled == listening then
        return
    end
    listening = enabled
    if enabled then
        events:RegisterEvent("TRAIT_CONFIG_UPDATED")
        if CludesUI.IS_FOREVER == true then
            events:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE")
        end
    else
        events:UnregisterAllEvents()
    end
end

local function Entry(provider)
    local Rec = entries[provider.key]
    if Rec then
        return Rec
    end
    Rec = { provider = provider, styleKey = "cdm:auraicon:" .. provider.key }
    local proxy = CreateFrame("Frame", nil, UIParent)
    proxy:Hide()
    proxy:EnableMouse(false)
    Rec.proxy = proxy
    -- Creation window: the CDM look's own regions, then the button fills the
    -- proxy (two-point anchors size it by the proxy for good).
    Rec.init = function(btnFrame, skinData)
        _AC.InitExtra(btnFrame, skinData)
        btnFrame:SetAllPoints(proxy)
    end
    entries[provider.key] = Rec
    return Rec
end

-- The host's laid-out size. The bar layout sizes every icon itself (Width or
-- Height Match, the per-row size offset, the spare pixels it spreads), and
-- AuraKit sizes the slot's border host from the style, not from the button,
-- so the look is cut for the host rather than for the bar's Icon Size. nil
-- before the first layout (the bar's Icon Size stands in).
local function HostSize(Rec)
    local owner = Rec.host
    if not owner then
        return nil
    end
    local wid, hgt = owner:GetSize()
    if
        type(wid) ~= "number"
        or type(hgt) ~= "number"
        or IsSecret(wid)
        or IsSecret(hgt)
        or wid <= 0
        or hgt <= 0
    then
        return nil
    end
    return wid, hgt
end

-- The slot's look: the bar's custom-aura look, cut for the host's size.
local function HostStyle(Rec, edge)
    local style = _AC.BuildStyle(edge)
    local wid, hgt = HostSize(Rec)
    if wid then
        style.width, style.height = wid, hgt
        if style.cdm then
            style.cdm.size = wid
        end
    end
    return style
end

-- The look's fingerprint: the bar settings a restyle carries, and the size
-- the look's own regions are cut for.
local function StyleSig(Rec, edge)
    local wid, hgt = HostSize(Rec)
    return _AC.StyleSig(edge)
        .. "|"
        .. tostring(edge.iconSize or 36)
        .. "|"
        .. tostring(wid)
        .. "x"
        .. tostring(hgt)
end

local function Restyle(Rec, barId)
    local edge = barDataByKey[barId]
    if not edge then
        return
    end
    local sig = StyleSig(Rec, edge)
    if Rec.styleBar == barId and Rec.styleSig == sig then
        return
    end
    local AK = CludesUI.AuraKit
    AK.styles[Rec.styleKey] = HostStyle(Rec, edge)
    Rec.styleBar, Rec.styleSig = barId, sig
    if AK.RestyleSoon then
        AK.RestyleSoon(Rec.styleKey)
    end
end

-- Levels follow the host: DecorateFrame levels its regions off the frame's
-- own level, which the reanchor's reparent moves.
local function Level(Rec)
    local owner, boxHolder = Rec.host, Rec.container
    if not (owner and boxHolder) then
        return
    end
    local lvl = owner:GetFrameLevel() + SLOT_LEVEL
    if Rec.level == lvl then
        return
    end
    Rec.level = lvl
    Rec.proxy:SetFrameLevel(lvl)
    boxHolder:SetFrameLevel(lvl + 1)
end

local function Build(Rec, include, sig)
    local edge = Rec.hostBar and barDataByKey[Rec.hostBar]
    if not edge then
        return
    end
    local AK = CludesUI.AuraKit
    AK.styles[Rec.styleKey] = HostStyle(Rec, edge)
    Rec.styleBar, Rec.styleSig = Rec.hostBar, StyleSig(Rec, edge)
    if Rec.container then
        AK.ReleaseContainer(Rec.container)
    end
    local boxHolder = AK.CreateContainerShell(Rec.proxy, { point = { "CENTER" } })
    AK.AddSlotToContainer(boxHolder, {
        key = "aura",
        filter = { "HELPFUL" },
        -- Helpful spell id includes on the player pass the identity gate
        -- whatever the spell's secrecy flag.
        candidateFilters = { includeSpellIDs = include },
        style = Rec.styleKey,
        extraInit = Rec.init,
    })
    AK.FinishContainer(boxHolder, "player")
    Rec.container, Rec.sig, Rec.level = boxHolder, sig, nil
    Level(Rec)
end

-- The reanchor placed the entry's frame on a bar: the slot follows it, and is
-- built (or built again for a new include set) on the AuraKit worker.
local function Attach(Rec, frame, barId)
    Rec.host, Rec.hostBar = frame, barId
    hostEntry[frame] = Rec
    placed[Rec] = true
    Listen(true)
    local proxy = Rec.proxy
    if proxy:GetParent() ~= frame then
        proxy:SetParent(frame)
        proxy:ClearAllPoints()
        proxy:SetAllPoints(frame)
        Rec.level = nil
    end
    if not proxy:IsShown() then
        proxy:Show()
    end
    if (not Rec.container or Rec.dirty) and not Rec.queued then
        Rec.dirty = nil
        local include, sig = Rec.provider.Include()
        if not Rec.container or sig ~= Rec.sig then
            Rec.queued = true
            AKWorker:Queue(function()
                Rec.queued = nil
                Build(Rec, include, sig)
            end, "cdm:auraicon")
        end
    end
    if Rec.container and Rec.styleBar ~= barId then
        Restyle(Rec, barId)
    end
end

-------------------------------------------------------------------------------
--  The host frame
-------------------------------------------------------------------------------
local function OnEnter(self)
    local fc = mod._ecmeFC[self]
    local edge = fc and fc.barKey and barDataByKey[fc.barKey]
    local spellRef = self._auraIconTip
    if not (edge and edge.showTooltip and spellRef) then
        return
    end
    -- Honor the global "Show Tooltips" mode (Blizzard Skin).
    if CludesUI._tooltipSuppressedByMode and CludesUI._tooltipSuppressedByMode(GameTooltip) then
        return
    end
    GameTooltip_SetDefaultAnchor(GameTooltip, self)
    GameTooltip:SetSpellByID(spellRef)
    if CludesUI._repointTooltipAtCursor then
        CludesUI._repointTooltipAtCursor(GameTooltip)
    end
    GameTooltip:Show()
end

-- The layout resized a host (a Width Match target moved, the bar's icon count
-- changed): its slot's look follows.
local function OnHostSize(self)
    local Rec = hostEntry[self]
    if Rec and Rec.host == self and Rec.container then
        Restyle(Rec, Rec.hostBar)
    end
end

-- Built once per bar and entry, kept in the preset frame map, so the reanchor
-- and every rebuild park it with the other injected frames.
local function HostFrame(barId, key)
    local fkey = barId .. ":auraicon:" .. key
    local frame = _presetFrames[fkey]
    if frame then
        return frame
    end
    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(36, 36)
    frame:Hide()
    frame:EnableMouse(true)
    if frame.SetMouseClickEnabled then
        frame:SetMouseClickEnabled(false)
    end
    local texture = frame:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints()
    mod.CdmOwnIconCrop(texture)
    frame.Icon = texture
    frame._tex = texture
    -- Never armed (the slot draws the aura's swipe); the decoration styles it
    -- like any icon's.
    local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    cd:SetHideCountdownNumbers(true)
    frame.Cooldown = cd
    frame._cooldown = cd
    frame._isPresetFrame = true
    frame._isAuraIconFrame = true
    frame.cooldownID = nil
    frame.cooldownInfo = nil
    frame.layoutIndex = 99999
    frame:SetScript("OnEnter", OnEnter)
    frame:SetScript("OnLeave", GameTooltip_Hide)
    frame:SetScript("OnSizeChanged", OnHostSize)
    _presetFrames[fkey] = frame
    return frame
end

local function PaintIdle(frame, provider)
    local art = provider.Icon()
    if art and frame._auraIconArt ~= art then
        frame._auraIconArt = art
        frame._tex:SetTexture(art)
    end
    local grey = provider.Desaturate() and true or false
    if frame._auraIconGrey ~= grey then
        frame._auraIconGrey = grey
        frame._tex:SetDesaturated(grey)
    end
    frame._auraIconTip = provider.tip
end

local function Place(barId, provider)
    if provider.Off and provider.Off() then
        return nil
    end
    local frame = HostFrame(barId, provider.key)
    -- Attach first: the include read is what tells the idle paint whether
    -- the entry's spell is known.
    Attach(Entry(provider), frame, barId)
    PaintIdle(frame, provider)
    return frame
end

-------------------------------------------------------------------------------
--  Phase 3 entry points
-------------------------------------------------------------------------------
-- A positive spell ID no Blizzard frame claimed: the frame of the provider
-- that draws it, or nil.
function mod.CDM_AuraIconFor(barId, spellRef)
    if pendingAliases[1] then
        ReadAliases()
    end
    local p = byID[spellRef]
    if not p then
        return nil
    end
    return Place(barId, p)
end

-- One provider per custom buff spell ID, made on first use. Its aura IDs are
-- the spell's own forms (typed, override, base), as on a buff bar.
local function BuffProvider(spellRef)
    local p = buffProviders[spellRef]
    if p then
        return p
    end
    p = {
        key = "buff:" .. spellRef,
        tip = spellRef,
        Include = function()
            local set = _AC.AddSpellForms({}, spellRef)
            local ids = {}
            for ident in pairs(set) do
                ids[#ids + 1] = ident
            end
            table.sort(ids)
            return set, table.concat(ids, ",")
        end,
        Icon = function()
            if not p.art then
                p.art = C_Spell.GetSpellTexture(spellRef)
            end
            return p.art
        end,
        Desaturate = function()
            return true
        end,
    }
    buffProviders[spellRef] = p
    return p
end

-- A custom buff's hosted marker no Blizzard frame or placeholder claimed: its
-- frame on this bar.
function mod.CDM_AuraIconForBuff(barId, spellRef)
    return Place(barId, BuffProvider(spellRef))
end

-------------------------------------------------------------------------------
--  After every reanchor; on a bar's look change
-------------------------------------------------------------------------------
-- Level the slots the pass placed (the reparent can move a host's level), run
-- their providers' checks, and let the listener go once nothing is placed.
function mod.CDM_AuraIconsPlaced()
    local any = false
    for Rec in pairs(placed) do
        placed[Rec] = nil
        any = true
        Level(Rec)
        local after = Rec.provider.Placed
        if after then
            after()
        end
    end
    if not any and listening then
        Listen(false)
    end
end

-- RefreshCDMIconAppearance: the slots on this bar take its new look.
function mod.CDM_AuraIconsRestyle(barId)
    for _, Rec in pairs(entries) do
        if Rec.container and Rec.hostBar == barId then
            Restyle(Rec, barId)
            Level(Rec)
        end
    end
end
