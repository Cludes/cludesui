if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_CDM_HookPresetCooldowns.lua
--
--  Dynamic potion display and the cooldown drain for CUI's own preset
--  frames (ProcessPresetCooldowns and its event lanes).
--  Reads the earlier hook files through ns and ns._hookInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._hookInternals
-- CludesUICdmHooks.lua or an earlier hook file failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local ECME = mod.ECME
local barDataByKey = mod.barDataByKey
local _ecmeFC = mod._ecmeFC
local GetTime = GetTime

local FD, CdmChargeInfoFor, PresetKeepsColor = Inner.FD, Inner.CdmChargeInfoFor, Inner.PresetKeepsColor
local _pcActive, _presetFrames = Inner._pcActive, Inner._presetFrames
local ApplyItemQualityPip = Inner.ApplyItemQualityPip

-- ---------------------------------------------------------------------------
-- Dynamic potion display for every pot preset carrying a displayOrder (Light's
-- Potential, Potion of Recklessness, Liquid Luster, health). The preset icon resolves
-- to the best variant actually in bags (preset.displayOrder, best first) and shows
-- THAT variant's icon, exact bag count, and tooltip -- 2 Fleeting pots show "2" even
-- with 50 regular ones in the bank of another rank. A combat potion icon walks its
-- families in the order its Combat Potion Icon menu saved (customActiveStates[key]
-- .potOrder, nil = the preset's own order) and, while its Swap Combat Pots When
-- Missing is on (potSwap; nil reads the old profile-wide switch), a family fully out
-- of bags falls through to the next. Identity is untouched (frame key, assigned-spell
-- key, saved settings and active states all stay on the entry's primary item; only
-- the DISPLAY resolves, so a running swipe survives the icon swapping variants).
-- Re-resolution is generation-gated: bag events, the menu's writes, and profile
-- changes bump/miss the gate; steady-state 10Hz ticks cost a few compares.
local PotSwap = {}
do
    local byPrimary, chains, chainByItem
    local famByKey = {}
    for _, fam in ipairs(mod.COMBAT_POTION_FAMILIES or {}) do
        famByKey[fam.key] = fam
    end

    -- The profile-wide switch the Extras section used to hold: the default of an
    -- icon whose own Swap Combat Pots When Missing was never set.
    function PotSwap.LegacySwap()
        local profile = ECME and ECME.db and ECME.db.profile
        return (profile and profile.cdmBars and profile.cdmBars.swapPotionsWhenMissing) == true
    end

    -- An icon's two Combat Potion Icon settings, from its customActiveStates entry
    -- (the per-icon menu's store, keyed by the entry key): swap on or off, and the
    -- family order as saved ("light,reck,luster") or nil. Plain reads, no allocation.
    function PotSwap.Settings(itemId)
        local cas = mod.GetCustomActiveState(-itemId)
        local swap = cas and cas.potSwap
        if swap == nil then swap = PotSwap.LegacySwap() end
        local sequence = cas and cas.potOrder
        if type(sequence) ~= "string" then sequence = nil end
        return swap == true, sequence
    end

    -- The family keys in the order an icon walks them: the saved order's valid keys,
    -- then every family it leaves out, in the preset's own order. Allocates: the
    -- chain memo below and the options menu are its callers.
    function PotSwap.Order(preset, orderStr)
        local result, seen = {}, {}
        if orderStr then
            for key in string.gmatch(orderStr, "[^,]+") do
                if famByKey[key] and not seen[key] then
                    seen[key] = true
                    result[#result + 1] = key
                end
            end
        end
        for _, key in ipairs(preset.potDefaultOrder or {}) do
            if famByKey[key] and not seen[key] then
                seen[key] = true
                result[#result + 1] = key
            end
        end
        return result
    end

    -- Preset for a pot's PRIMARY item id (nil for every non-pot preset).
    function PotSwap.ByPrimary(itemId)
        if not byPrimary then
            byPrimary = {}
            for _, pr in ipairs(mod.CDM_ITEM_PRESETS or {}) do
                if pr.displayOrder then byPrimary[pr.itemID] = pr end
            end
        end
        return byPrimary[itemId]
    end

    PotSwap.gen = 1
    function PotSwap.Bump() PotSwap.gen = PotSwap.gen + 1 end

    -- Ordered item ids an icon walks: for a combat potion, the first family's
    -- displayOrder with every later family's appended while the icon swaps; for
    -- any other pot preset its own displayOrder. One table per distinct answer,
    -- shared by every icon that resolves to it, memoized per item key against the
    -- generation and the two settings, so the polls (FakeActive) never rebuild it.
    function PotSwap.Chain(preset, itemId)
        if not preset.potFamily then return preset.displayOrder end
        local swap, orderStr = PotSwap.Settings(itemId)
        if not chainByItem then chainByItem = {} end
        local m = chainByItem[itemId]
        if m and m.gen == PotSwap.gen and m.swap == swap and m.order == orderStr then return m.chain end
        local keyList = PotSwap.Order(preset, orderStr)
        local sig = (swap and "1" or "0") .. table.concat(keyList, ",")
        if not chains then chains = {} end
        local chain = chains[sig]
        if not chain then
            chain = {}
            for index = 1, (swap and #keyList or math.min(1, #keyList)) do
                local fam = famByKey[keyList[index]]
                local entries = fam and fam.preset.displayOrder
                if entries then
                    for jdx = 1, #entries do
                        chain[#chain + 1] = entries[jdx]
                    end
                end
            end
            chains[sig] = chain
        end
        if not m then
            m = {}
            chainByItem[itemId] = m
        end
        m.gen, m.swap, m.order, m.chain = PotSwap.gen, swap, orderStr, chain
        return chain
    end

    -- Resolve + stamp a pot-preset frame's display variant. Returns the display
    -- item id, or nil when the frame is not a resolving pot preset (every other
    -- item preset and user-added custom items -- their paths are untouched).
    -- The primary-id check matters: a user who manually adds one specific
    -- variant's item id gets that literal item, never the dynamic display.
    -- Nothing owned anywhere in the chain falls back to the primary item at
    -- count 0, so the icon keeps its slot (greyed) instead of vanishing.
    function PotSwap.Ensure(frame)
        local preset = frame._presetData
        if not (preset and preset.displayOrder and frame._presetItemID == preset.itemID) then return nil end
        local swap, orderStr = PotSwap.Settings(frame._presetItemID)
        if
            frame._potResolveGen == PotSwap.gen
            and frame._potResolveSwap == swap
            and frame._potResolveOrder == orderStr
        then
            return frame._displayItemID
        end
        frame._potResolveGen, frame._potResolveSwap, frame._potResolveOrder = PotSwap.gen, swap, orderStr
        local chain = PotSwap.Chain(preset, frame._presetItemID)
        local ident, count
        for index = 1, #chain do
            local c = C_Item.GetItemCount(chain[index], false, true) or 0
            if c > 0 then
                ident, count = chain[index], c
                break
            end
        end
        if not ident then
            ident, count = preset.itemID, 0
        end
        frame._displayCount = count
        if frame._displayItemID ~= ident then
            frame._displayItemID = ident
            -- preset.icon is PICKER-ONLY art (the current-tier pot): every resolved
            -- variant, the primary included, paints its own item art so the icon
            -- always matches the counted/tooltipped variant.
            local iconTex = (C_Item.GetItemIconByID and C_Item.GetItemIconByID(ident)) or preset.icon
            if frame._tex then frame._tex:SetTexture(iconTex) end
        end
        return ident
    end
end
-- FakeActive (cooldown-state poll + cast-trigger mapping) reads the chain for a
-- pot preset's primary item id; nil for anything else.
mod.GetPresetPotChain = function(itemId)
    local pr = PotSwap.ByPrimary(itemId)
    return pr and PotSwap.Chain(pr, itemId) or nil
end
-- The per-icon menu: a Combat Potion Icon write forces every pot frame to
-- re-resolve on the next pass.
mod._BumpPotResolveGen = PotSwap.Bump
-- The per-icon menu's reads: the old profile-wide swap switch (the default of an
-- icon whose own is unset) and an icon's family order from its saved string.
mod.PotSwapLegacyDefault = PotSwap.LegacySwap
mod.PotOrderFor = PotSwap.Order

-- The options preview: the art an item entry's icon shows in game and the item
-- its tooltip names, so the preview slot matches the live bar. A frame under the
-- key on that bar answers first (the preset's own frame with its resolved
-- variant painted, or Blizzard's own row with Blizzard's art); with none up, the
-- variant PotSwap would resolve from the bags; else the primary item.
-- Options-time only.
function mod.ItemEntryPreview(barId, key)
    local itemId = -key
    local icons = barId and mod.cdmBarIcons and mod.cdmBarIcons[barId]
    if icons then
        for index = 1, #icons do
            local frame = icons[index]
            local fc = frame and _ecmeFC[frame]
            if fc and fc.spellID == key then
                local texture = frame._tex or frame.Icon
                local art = texture and texture.GetTexture and texture:GetTexture()
                if art then return art, frame._displayItemID or itemId end
                break
            end
        end
    end
    local pr = PotSwap.ByPrimary(itemId)
    if pr then
        local chain = PotSwap.Chain(pr, itemId)
        for index = 1, #chain do
            if (C_Item.GetItemCount(chain[index], false, true) or 0) > 0 then
                return C_Item.GetItemIconByID(chain[index]) or C_Item.GetItemIconByID(itemId), chain[index]
            end
        end
    end
    return C_Item.GetItemIconByID(itemId), itemId
end

-- Count (charges included) of an item preset's item: its own count, else, for the
-- preset's PRIMARY item only, the sum of the family alts. Returns total and the
-- first owned id. The picker only ever stores -(preset.itemID), so a frame
-- sitting on an ALT id can only have come from the user typing that exact item id
-- into Custom Item ID -- they asked for that rank, not for the family.
-- Frames still carry _presetData either way: the preset icon and the keybind
-- fallback (which deliberately answers across ranks) want it. Only this
-- family-wide read is primary-only -- summing the family's bag counts made a
-- hand-added rank-2 pot report its rank-1 siblings as its own count, point
-- _itemCdSource at a sibling's cooldown and, with Hide Items if Missing on, stay
-- on the bar while the user owned none of it. Two such entries then showed the
-- same count off the same art (ranks share an icon), which reads as one pot
-- tracked twice. Mirrors PotSwap.Ensure's own primary check. On ns: 200-local cap.
function mod._ItemPresetCount(pd, itemId)
    local sum = C_Item.GetItemCount(itemId, false, true) or 0
    local owned = sum > 0 and itemId or nil
    if sum == 0 and pd and pd.altItemIDs and itemId == pd.itemID then
        for _, altID in ipairs(pd.altItemIDs) do
            local c = C_Item.GetItemCount(altID, false, true) or 0
            sum = sum + c
            if not owned and c > 0 then owned = altID end
        end
    end
    return sum, owned
end

-- That count for a non-pot item preset frame. On ns: 200-local cap.
function mod._ReadItemPresetCount(frame) return mod._ItemPresetCount(frame._presetData, frame._presetItemID) end

-- Pact of Gluttony (386689) decides which stone the player conjures: with it only
-- Demonic Healthstones (224464), without it only Healthstones (5512). The other
-- stone's entry never shows, not even dimmed. Read by the reanchor pass; talent and
-- spell changes always queue one. On ns: 200-local cap.
function mod._HealthstoneHiddenByPact(itemId)
    if itemId ~= 5512 and itemId ~= 224464 then return false end
    local pact = C_SpellBook.IsSpellKnown(386689) == true
    if itemId == 5512 then return pact end
    return not pact
end

-- Blizzard's native Healthstone and Demonic Healthstone rows show no count of
-- their own: each shows its preset's count, read as the preset icon reads it.
-- On ns: 200-local cap.
do
    local hooked = setmetatable({}, { __mode = "k" })
    local inCombat = false
    local CI = mod._internals
    CI.inCombatSetters[#CI.inCombatSetters + 1] = function(val) inCombat = val end

    -- The stone preset an entry key stands for, else nil.
    local function StonePreset(key)
        local p = key and mod.ItemPresetForKey(key)
        if p and (p.key == "healthstone" or p.key == "demonic_healthstone") then return p end
    end

    local function Apply(widget)
        local fc = _ecmeFC[widget]
        local cc = widget.ChargeCount
        local fontStr = cc and cc.Current
        -- Pooled frames: the cdID check drops a frame Blizzard re-used before the next reanchor.
        local p = fc
            and fontStr
            and fc.healthstoneCdID
            and widget.cooldownID == fc.healthstoneCdID
            and StonePreset(fc.spellID)
        if not p then return end
        local edge = fc.barKey and barDataByKey[fc.barKey]
        local show = not edge or edge.showItemCount ~= false
        if show and edge and edge.itemCountOOC and inCombat then show = false end
        local count = show and mod._ItemPresetCount(p, p.itemID) or 0
        if count > 0 then
            fontStr:SetText(count)
            cc:Show()
        else
            fontStr:SetText("")
            cc:Hide()
        end
    end

    function mod._ClaimNativeHealthstone(widget, cdID)
        local fc = _ecmeFC[widget]
        if not (fc and StonePreset(fc.spellID)) then return end
        fc.healthstoneCdID = cdID
        mod._nativeHealthstoneClaimed = true
        if not hooked[widget] and widget.RefreshSpellChargeInfo then
            hooked[widget] = true
            hooksecurefunc(widget, "RefreshSpellChargeInfo", Apply)
        end
        Apply(widget)
    end

    function mod._RefreshNativeHealthstoneCounts()
        if not mod._nativeHealthstoneClaimed then return end
        for vi = 1, 2 do
            local viewer = Inner.GetViewerFrame(vi)
            local pool = viewer and viewer.itemFramePool
            if pool and pool.EnumerateActive then
                for widget in pool:EnumerateActive() do
                    Apply(widget)
                end
            end
        end
    end
end

-- Guard: after ENCOUNTER_END clears item-preset caches, subsequent events
-- fire before Blizzard has finished resetting potion CDs. Without this guard
-- the update loop re-caches stale cooldown data from C_Item.GetItemCooldown.
-- Uses a timestamp so the grace period works regardless of event ordering.
local _encounterResetUntil = 0

local _racialCdListener = CreateFrame("Frame")
_racialCdListener:RegisterEvent("SPELL_UPDATE_COOLDOWN")
_racialCdListener:RegisterEvent("SPELL_UPDATE_CHARGES")
_racialCdListener:RegisterEvent("BAG_UPDATE_COOLDOWN")
_racialCdListener:RegisterEvent("BAG_UPDATE_DELAYED")
-- Usability edges for the custom-spell resource tint (UniqueEvent:
-- client-coalesced to at most one fire per frame).
_racialCdListener:RegisterEvent("SPELL_UPDATE_USABLE")
_racialCdListener:RegisterEvent("ENCOUNTER_END")
_racialCdListener:RegisterEvent("CHALLENGE_MODE_START")
_racialCdListener:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
_racialCdListener:RegisterEvent("PLAYER_REGEN_ENABLED")

-- Combat lockout spellID -> itemID map (built once from presets)
local _combatLockoutSpells = {}
for _, preset in ipairs(mod.CDM_ITEM_PRESETS or {}) do
    if preset.combatLockout and preset.spellID then _combatLockoutSpells[preset.spellID] = preset.itemID end
end

-------------------------------------------------------------------------------
--  Per-bar "Suppress GCD" for CUI's OWN preset frames.
--
--  The setting is implemented as a hooksecurefunc on the cooldown's
--  SetSwipeColor (see DecorateFrame), which reaches BLIZZARD-owned CDM icons
--  only: Blizzard repaints their swipe colour as the cooldown state changes, so
--  the hook gets a chance to alpha-0 it. Preset frames (racials and user-added
--  custom spells) are painted by US -- swipe colour is written once at decorate
--  time and only GEOMETRY is driven afterwards -- so the hook never fires for
--  them and the GCD swipe stayed full alpha while the rest of the bar
--  suppressed it. EVERY place that drives a preset frame's SPELL cooldown must
--  call this right after pushing the geometry. ITEM-backed preset frames
--  (trinket slots, potion/item presets) deliberately do NOT route through here:
--  they drop the GCD out of the GEOMETRY with a dur > 1.5 test before
--  SetCooldown, so there's no GCD swipe to hide. cdInfo and barKey are optional
--  (callers that already hold them pass them in rather than paying for the
--  lookup twice); barKey must be passed by callers running BEFORE the frame's
--  cache entry is stamped.
-------------------------------------------------------------------------------
local function ApplyPresetGCDSwipe(frame, spellRef, cdInfo, barId)
    local cdF = frame and frame._cooldown
    if not (spellRef and cdF and cdF.SetSwipeColor) then return end
    if not barId then
        local fc = _ecmeFC[frame]
        barId = fc and fc.barKey
    end
    local edge = barId and barDataByKey[barId]
    -- Per-spell Suppress GCD ORs into the bar toggle (bar ON = per-spell
    -- no-op); session-gated so unused installs never pay the resolve.
    local suppress = (edge and edge.suppressGCD) or false
    if not suppress and mod._cdmAnySuppressGcd then
        local ss = mod._ResolveCdmSS and mod._ResolveCdmSS(frame)
        suppress = (ss and ss.suppressGCD) or false
    end
    local hide = false
    if suppress then
        if cdInfo == nil and C_Spell and C_Spell.GetSpellCooldown then
            cdInfo = C_Spell.GetSpellCooldown(spellRef)
        end
        if cdInfo and cdInfo.isOnGCD then
            -- Same charge carve-out as the hook: a charge spell mid-recharge is
            -- showing its RECHARGE, never a GCD, and alpha-0'ing that would
            -- blank the recharge for a whole GCD every time another ability is
            -- pressed. Read it from the stable charge data (maxCharges +
            -- isActive), never the secret currentCharges.
            -- Resolved through CdmChargeInfoFor so this copy cannot drift from
            -- the hook's answer; preset frames are ours rather than
            -- CooldownViewer items, so it falls back to the spellbook
            -- resolution for them.
            local ci = CdmChargeInfoFor(frame, spellRef)
            hide = not (ci and (ci.maxCharges or 0) > 1 and ci.isActive == true)
        end
    end
    -- Re-assert while suppressed rather than only on the rising edge: an
    -- appearance refresh repaints the swipe from bar data and would otherwise
    -- un-hide it until the next state change. The restore arm fires on the
    -- falling edge alone, so a frame we never suppressed keeps its own paint
    -- and nothing else is fought for ownership of the colour.
    local fd = FD(frame)
    if hide then
        frame._gcdSwipeHidden = true
        fd._isProcessingOverride = true
        cdF:SetSwipeColor(0, 0, 0, 0)
        fd._isProcessingOverride = false
    elseif frame._gcdSwipeHidden then
        frame._gcdSwipeHidden = nil
        fd._isProcessingOverride = true
        cdF:SetSwipeColor(0, 0, 0, (edge and edge.swipeAlpha) or 0.7)
        fd._isProcessingOverride = false
    end
end
mod.ApplyPresetGCDSwipe = ApplyPresetGCDSwipe

-- Dirty flag: high-frequency events (SPELL_UPDATE_COOLDOWN, BAG_UPDATE_COOLDOWN)
-- just set this flag; the BuffTicker (10Hz) processes it, coalescing dozens of
-- per-GCD events into a single update pass.
local _presetCdDirty = false
-- True when the last drain pass found every preset frame settled (no running
-- cooldown/desaturation/resource dim/shown charge text). While settled,
-- high-frequency noise events (SPELL_UPDATE_COOLDOWN fires steadily even at
-- idle) no longer arm the drain -- every settled->unsettled transition arrives
-- through the fast lanes (player cast, bag update, combat edges).
local _pcAllSettled = false

-- The actual update work, called from BuffTicker at 10Hz max.
local function ProcessPresetCooldowns()
    _presetCdDirty = false
    local anyUnsettled = false
    local nowTime = GetTime()
    -- 5s full sweep: reads every spell-preset frame regardless of arms --
    -- the self-heal net for any missed arm edge (worst staleness = 5s,
    -- once). Between sweeps, ready un-armed frames are skipped entirely.
    local fullSweep
    if nowTime >= (mod._pcFullNext or 0) then
        fullSweep = true
        mod._pcFullNext = nowTime + 5
    end
    -- Iterate the LIVE set (shown drain-relevant frames only), not the
    -- session-cumulative _presetFrames reuse map -- see _RegisterPresetLive. The
    -- IsShown() belt is redundant by construction but costs one call per LIVE frame.
    for frame in pairs(_pcActive) do
        if frame:IsShown() then
            if (frame._isRacialFrame or frame._isCustomSpellFrame) and not frame._isCustomBuffFrame then
                -- Cache extracted spellID on the frame to avoid regex every tick
                local spellRef = frame._cachedPresetSID
                if not spellRef then
                    local m = frame._pfKey and frame._pfKey:match(":(%d+)$")
                    spellRef = m and tonumber(m)
                    frame._cachedPresetSID = spellRef
                end
                -- Read-skip: a READY frame with no pending arm cannot have
                -- changed state -- every start edge arms it (cast/named/wave lanes
                -- set _cdPushArm, usability edges set _cdEvalArm), and the 5s sweep
                -- heals anything missed. Running frames (_lastOnRealCD ~= false,
                -- incl. never-read nil) and dimmed frames keep polling as the
                -- eventless ready-edge belt. A visible charge text no longer
                -- holds the frame in the poll: its count only moves on edges
                -- that arm (a cast unsettles the drain and its named events arm
                -- the exact frame; a charge regen completing while settled
                -- wakes via the listener's settled-state charge lane).
                if
                    spellRef
                    and (
                        fullSweep
                        or frame._cdPushArm
                        or frame._cdEvalArm
                        or frame._lastOnRealCD ~= false
                        or frame._lastVertexDim
                    )
                then
                    local textArm = (fullSweep or frame._cdPushArm or frame._cdEvalArm) and true or nil
                    frame._cdEvalArm = nil
                    local cdInfo = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellRef)
                    local onRealCD = (cdInfo and cdInfo.isActive and not cdInfo.isOnGCD) and true or false
                    -- Push-on-edge: the swipe widget animates itself once armed,
                    -- so the duration object is re-pushed only when an event
                    -- lane armed it (cast, named/wave cooldown event, rebuild).
                    -- Belt: a state flip the lanes missed re-arms on this tick
                    -- (the old unconditional push had the same 10Hz latency).
                    if frame._lastOnRealCD ~= onRealCD then
                        frame._lastOnRealCD = onRealCD
                        frame._cdPushArm = true
                        textArm = true
                    end
                    if frame._cdPushArm then
                        frame._cdPushArm = false
                        local durObj = C_Spell.GetSpellCooldownDuration
                            and C_Spell.GetSpellCooldownDuration(spellRef)
                        if durObj and frame._cooldown and frame._cooldown.SetCooldownFromDurationObject then
                            frame._cooldown:SetCooldownFromDurationObject(durObj, true)
                        end
                    end
                    if onRealCD then anyUnsettled = true end
                    -- Binary desat from the SAME readable bools this pass already
                    -- holds: the desat curve is a STEP (0->0, 0.001->1), so it
                    -- reduces to (onRealCD and 1 or 0). GCD-only stays saturated,
                    -- keep-color presets stay at 0, write is edge-gated;
                    -- ApplySpellDesaturation nils the memo on out-of-band writes (frame create/dirty path).
                    local desat = (onRealCD and not PresetKeepsColor(frame)) and 1 or 0
                    if frame._tex and frame._lastDesatVal ~= desat then
                        frame._lastDesatVal = desat
                        frame._tex:SetDesaturation(desat)
                    end
                    -- Suppress GCD: this pass drives the geometry, so it also owns
                    -- hiding the swipe when that geometry is only a GCD.
                    ApplyPresetGCDSwipe(frame, spellRef, cdInfo)
                    -- Resource check: dim vertex color when not enough resources
                    -- Only for custom spells (not racials -- racials don't cost resources).
                    -- Out of Range Coloring (opt-in) outranks the dim; its answer
                    -- (f._rangeOut) is kept by events and only painted here.
                    if frame._isCustomSpellFrame and frame._tex then
                        mod.PaintCustomSpellTint(frame, spellRef, onRealCD)
                    end
                    if frame._lastVertexDim then anyUnsettled = true end
                    -- "Show Charges" (opt-in, CD/utility custom spells only):
                    -- Blizzard reports no charge frame for a manually-added spell,
                    -- so on request show its count -- the display charge count when
                    -- the spell actually has charges, else the cast/usable count.
                    -- Gated by ns._cdmAnyCustomForceCount + a lazy fontstring, so it
                    -- costs nothing unless a custom spell opts in. Rides this same
                    -- 10Hz-when-dirty pass -- no extra OnUpdate.
                    if mod._cdmAnyCustomForceCount and frame._isCustomSpellFrame then
                        local fcF = _ecmeFC[frame]
                        local bkF = fcF and fcF.barKey
                        local sdF = bkF and mod.GetBarSpellData and mod.GetBarSpellData(bkF)
                        local forceCount = sdF
                            and sdF.customSpellForceCount
                            and sdF.customSpellForceCount[spellRef]
                        if forceCount then
                            -- Render only on ARMED passes: the count moves only
                            -- on edges that arm (gate comment above). An armed
                            -- pass re-reads; an unarmed pass keeps the text --
                            -- and no longer blocks the drain from settling.
                            if textArm then
                                if not frame._castCountText then
                                    frame._castCountText = frame:CreateFontString(nil, "OVERLAY")
                                    -- Match the bar's native stack/charge text styling
                                    -- (font, size, color, anchor, X/Y offset);
                                    -- RefreshCDMIconAppearance keeps it in sync afterwards.
                                    mod.StyleCustomChargeText(frame, bkF)
                                end
                                local chargeInfo = C_Spell.GetSpellCharges
                                    and C_Spell.GetSpellCharges(spellRef)
                                local num = (
                                    chargeInfo
                                    and C_Spell.GetSpellDisplayCount
                                    and C_Spell.GetSpellDisplayCount(spellRef)
                                )
                                    or (C_Spell.GetSpellCastCount and C_Spell.GetSpellCastCount(spellRef))
                                -- The count is a SECRET value in Midnight (cannot be read or
                                -- compared -- issecretvalue was making the old code bail), so
                                -- render it Blizzard's way: TruncateWhenZero turns it into a
                                -- display-safe string and drops it at zero, without reading
                                -- the value. pcall because it can throw; failure -> hide.
                                local success, text
                                if C_StringUtil and C_StringUtil.TruncateWhenZero then
                                    success, text = pcall(C_StringUtil.TruncateWhenZero, num)
                                end
                                if success and text then
                                    frame._castCountText:SetText(text)
                                    if not frame._castCountText:IsShown() then frame._castCountText:Show() end
                                elseif frame._castCountText:IsShown() then
                                    frame._castCountText:SetText("")
                                    frame._castCountText:Hide()
                                end
                            end
                        elseif frame._castCountText and frame._castCountText:IsShown() then
                            frame._castCountText:SetText("")
                            frame._castCountText:Hide()
                            frame._lastCastCount = nil
                        end
                    end
                end
            elseif
                frame._isItemPresetFrame
                and frame._presetItemID
                and nowTime >= _encounterResetUntil
                -- Item read-skip (probe-proven capture #12: the item branch was the
                -- drain's entire remaining cost): a READY, un-armed, un-desaturated item
                -- frame cannot change state -- loot/bag edges arm it, lockout/desat keep
                -- it polling, an on-cd frame polls for its own expiry edge, and the 5s
                -- sweep heals anything missed.
                and (
                    fullSweep
                    or frame._itemWalkArm ~= false
                    or frame._countArm ~= false
                    or frame._inCombatLockout
                    or frame._lastDesat
                    or (frame._cdStart and frame._cdDur and nowTime < frame._cdStart + frame._cdDur)
                )
            then
                -- Pot presets: re-resolve the display variant (generation-gated,
                -- one compare when nothing changed) and drive count/cooldown off
                -- the resolved chain. Every other item preset keeps the legacy
                -- primary-then-alts walk byte-identically.
                local dispID = PotSwap.Ensure(frame)
                -- A variant flip moves the cooldown source: force a re-walk.
                if dispID ~= frame._lastDispID then
                    frame._lastDispID = dispID
                    frame._itemWalkArm = true
                end
                -- Walk-on-edge: item cooldowns only move on BAG_UPDATE_COOLDOWN
                -- / cast / bag-content / encounter-reset edges, all of which arm
                -- the walk. Between edges the cached start/dur drives itemOnCD
                -- and the armed widget completes on its own (nil arm = first
                -- pass for this frame, walk once).
                if frame._itemWalkArm ~= false then
                    frame._itemWalkArm = false
                    local getContainerCD = C_Container and C_Container.GetItemCooldown
                    local start, dur
                    -- SINGLE-ID cooldown probe (user-directed model, the reference
                    -- watcher's shape): ownership picks ONE active id, re-pointed ONLY
                    -- on bag-CONTENT edges (PotSwap's resolver for pots, the count walk
                    -- below for the rest); cooldown events probe exactly that id. The
                    -- shared potion cd reports on every OWNED id, and after drinking
                    -- the LAST of a rank it lives on the id just used -- so the
                    -- last-OWNED id is remembered as the cd source while nothing is
                    -- owned. Cast-driven item-GCD noise (BAG_UPDATE_COOLDOWN fires per
                    -- ability press) now costs 1-2 calls instead of a dozen bag scans.
                    local probeID
                    if dispID then
                        if (frame._displayCount or 0) > 0 then
                            frame._lastOwnedDispID = dispID
                            probeID = dispID
                        else
                            probeID = frame._lastOwnedDispID or dispID
                        end
                    else
                        probeID = frame._itemCdSource or frame._presetItemID
                    end
                    if getContainerCD then
                        start, dur = getContainerCD(probeID)
                    end
                    if not (start and dur and dur > 1.5) then
                        start, dur = C_Item.GetItemCooldown(probeID)
                    end
                    -- One-time seed per frame object: post-/reload a residual
                    -- cd can live on an id we have no memory of (used before
                    -- the reload, nothing owned now) -- find and remember it.
                    if not frame._cdSeeded then
                        frame._cdSeeded = true
                        if not (start and dur and dur > 1.5) then
                            local entries = dispID and PotSwap.Chain(frame._presetData, frame._presetItemID)
                                or (frame._presetData and frame._presetData.altItemIDs)
                            if entries then
                                for index = 1, #entries do
                                    local cid = entries[index]
                                    if cid ~= probeID then
                                        if getContainerCD then
                                            start, dur = getContainerCD(cid)
                                        end
                                        if not (start and dur and dur > 1.5) then
                                            start, dur = C_Item.GetItemCooldown(cid)
                                        end
                                        if start and dur and dur > 1.5 then
                                            if dispID then
                                                frame._lastOwnedDispID = cid
                                            else
                                                frame._itemCdSource = cid
                                            end
                                            break
                                        end
                                    end
                                end
                            end
                        end
                    end
                    if start and dur and dur > 1.5 then
                        frame._cooldown:SetCooldown(start, dur)
                        frame._cdStart = start
                        frame._cdDur = dur
                    elseif
                        not (frame._cdStart and frame._cdDur and (nowTime < frame._cdStart + frame._cdDur))
                    then
                        frame._cooldown:Clear()
                        frame._cdStart = nil
                        frame._cdDur = nil
                    end
                end
                local itemOnCD = frame._cdStart and frame._cdDur and (nowTime < frame._cdStart + frame._cdDur)
                if itemOnCD or frame._inCombatLockout then anyUnsettled = true end
                local sum
                if dispID then
                    -- Exact count of the resolved variant only -- never a sum
                    -- across ranks/families (2 Fleeting shows 2, even with 50
                    -- regular rank 1s in the bags).
                    sum = frame._displayCount or 0
                    -- Consume the arm here too: resolving pots count via PotSwap
                    -- (_displayCount), so without this the read-skip gate saw pots as
                    -- count-armed FOREVER and never skipped them (probe capture #12).
                    frame._countArm = false
                elseif frame._countArm ~= false then
                    -- Count-on-edge: item counts move with bag contents
                    -- (BAG_UPDATE_DELAYED), a use-cast, or a charge-only
                    -- change (BAG_UPDATE_COOLDOWN recheck), all of which arm.
                    -- This content edge also re-points the single watched cd
                    -- id (f._itemCdSource): first owned id wins; while
                    -- nothing is owned the LAST owned id is kept (the shared
                    -- cd lives on the id that was just used).
                    frame._countArm = false
                    local owned
                    sum, owned = mod._ReadItemPresetCount(frame)
                    if owned then frame._itemCdSource = owned end
                    frame._cachedTotal = sum
                else
                    sum = frame._cachedTotal or 0
                end
                if frame._itemCountText then
                    local fc = _ecmeFC[frame]
                    local bk = fc and fc.barKey
                    local edge = bk and barDataByKey[bk]
                    local showIC = not edge or edge.showItemCount ~= false
                    -- Show Item Count "Out of Combat" mode: this update path
                    -- force-Shows on count changes, so it must respect the
                    -- combat gate or it would re-show the text mid-combat.
                    if showIC and edge and edge.itemCountOOC and InCombatLockdown() then showIC = false end
                    -- Count shows for ANY owned stack, including the last
                    -- one; it hides only at 0 (where the desaturation below
                    -- already reads as "none left").
                    local displayCount = showIC and (sum > 0) and sum or nil
                    if displayCount then
                        if frame._lastItemCount ~= displayCount then
                            frame._itemCountText:SetText(displayCount)
                            frame._lastItemCount = displayCount
                        end
                        if not frame._itemCountText:IsShown() then frame._itemCountText:Show() end
                    elseif frame._lastItemCount then
                        frame._itemCountText:SetText("")
                        frame._itemCountText:Hide()
                        frame._lastItemCount = nil
                    end
                end
                do
                    -- Quality pip follows the variant actually being SHOWN: a pot
                    -- preset resolves its icon across ranks, so keying this on the
                    -- primary would label the icon with a rank it is not drawing.
                    local fc2 = _ecmeFC[frame]
                    local bk2 = fc2 and fc2.barKey
                    local bd2 = bk2 and barDataByKey[bk2]
                    ApplyItemQualityPip(
                        frame,
                        frame._displayItemID or frame._presetItemID,
                        bd2 and bd2.showItemQuality == true
                    )
                end
                local shouldDesat = (sum == 0 or itemOnCD or frame._inCombatLockout) and true or false
                if shouldDesat ~= frame._lastDesat then
                    frame._lastDesat = shouldDesat
                    if frame._tex then frame._tex:SetDesaturated(shouldDesat) end
                end
            end
        end
    end
    _pcAllSettled = not anyUnsettled
end
mod._ProcessPresetCooldowns = ProcessPresetCooldowns
mod._isPresetCdDirty = function() return _presetCdDirty end
-- Setter so the inject path can request a preset desaturation re-evaluation. A
-- full rebuild wipes and re-injects preset frames with no cached desat state; if
-- no game event (bag/cooldown/combat) follows -- e.g. an in-panel sync/import --
-- ProcessPresetCooldowns would never run and an unowned item would stay saturated.
mod._MarkPresetCdDirty = function()
    _presetCdDirty = true
    _pcAllSettled = false
    if mod.ArmBuffTicker then mod.ArmBuffTicker() end
end

-- "Hide Items if Missing": detect when a tracked consumable's bag presence
-- flips (acquired or fully used up) for any bar that opted in, and queue a
-- reanchor so the injection pass re-evaluates and shows/hides it. Cheap: only
-- iterates the handful of injected preset frames, and only counts items for
-- frames whose owning bar has the setting on.
local function CheckItemPresenceForHide()
    local changed = false
    for _, frame in pairs(_presetFrames) do
        if frame._isItemPresetFrame and frame._presetItemID then
            local edge = frame._ownerBarKey and barDataByKey[frame._ownerBarKey]
            -- A stone the Pact of Gluttony rule hides is never injected, so its
            -- stale presence cache must not queue a reanchor on every bag edge.
            if edge and edge.hideItemsIfMissing and not mod._HealthstoneHiddenByPact(frame._presetItemID) then
                local sum
                if PotSwap.Ensure(frame) then
                    -- Pot presets: present = the resolved chain owns anything
                    -- (partner family counts while the swap toggle is on).
                    sum = frame._displayCount or 0
                else
                    sum = mod._ReadItemPresetCount(frame)
                end
                if (sum > 0) ~= frame._hidePresenceCached then changed = true end
            end
        end
    end
    if changed and mod.QueueReanchor then mod.QueueReanchor() end
end

-- Readable plain number: payload ids can in principle be secret in combat;
-- comparing a secret throws, so an unreadable id is treated as absent.
local function _PlainNum(val) return type(val) == "number" and (not canaccessvalue or canaccessvalue(val)) end

-- Trailing flush for the loot-storm cap: a bag fire swallowed inside the
-- window re-arms on the first listener event past it, or at the window's end
-- when nothing else fires (a conjured stone's second bag fire lands inside
-- the window, and a quiet world would otherwise keep its count stale until
-- some unrelated event). On ns: 200-local cap.
mod._pcBagFlush = function()
    mod._pcBagPend = nil
    mod._pcBagNext = GetTime() + 0.5
    -- Bag contents changed: pot-preset display variants must re-resolve before
    -- the presence check, which reads the resolution.
    PotSwap.Bump()
    CheckItemPresenceForHide()
    -- Contents are the only thing that changes item counts, and a new stack can
    -- move the displayed cooldown source too: re-walk both. (Live set: hidden
    -- frames re-arm on their Show edge.)
    for frame in pairs(_pcActive) do
        if frame._isItemPresetFrame then
            frame._itemWalkArm = true
            frame._countArm = true
        end
    end
    _presetCdDirty = true
    _pcAllSettled = false
    if mod.ArmBuffTicker then mod.ArmBuffTicker() end
end
mod._pcBagFlushTimerFn = function()
    mod._pcBagFlushQueued = nil
    if mod._pcBagPend then mod._pcBagFlush() end
end

_racialCdListener:SetScript("OnEvent", function(_, evt, a1, a2, a3, a4)
    if mod._pcBagPend and GetTime() >= (mod._pcBagNext or 0) then mod._pcBagFlush() end
    -- Infrequent events: handle immediately and return
    if evt == "BAG_UPDATE_DELAYED" then
        mod._RefreshNativeHealthstoneCounts()
        -- Loot-storm cap (probe-proven capture #12: mob-farming loot fires
        -- this in bursts, and each fire re-armed variant re-resolves + chain
        -- walks + bag-count scans -- the drain's dominant real cost). At
        -- most two re-arm cycles per second; a burst's trailing changes land
        -- on the head flush or the queued flush at the window's end.
        local nowB = GetTime()
        if nowB >= (mod._pcBagNext or 0) then
            mod._pcBagFlush()
        else
            -- Swallowed by the cap: flush on the first event after the
            -- window (see the head of this handler), or at its end at the
            -- latest -- one queued flush per window.
            mod._pcBagPend = true
            if not mod._pcBagFlushQueued then
                mod._pcBagFlushQueued = true
                C_Timer.After(mod._pcBagNext - nowB, mod._pcBagFlushTimerFn)
            end
        end
        return
    end
    if evt == "BAG_UPDATE_COOLDOWN" then
        mod._RefreshNativeHealthstoneCounts()
        -- Charge-only item count changes (a used Healthstone charge, a Soulwell
        -- refill) move no bag contents, so no BAG_UPDATE fires; a used charge
        -- lands with this event, after the cast arm already read the old count.
        -- Re-read the shown non-pot item counts and arm only on a real change.
        -- A count crossing zero also re-runs the Hide Items if Missing check,
        -- which otherwise only bag-content edges drive. Only items held now:
        -- nothing held has no charges to change (gaining one is a bag-content
        -- edge), and this event fires on nearly every ability press, where an
        -- unheld family preset would count every one of its ranks.
        local hit, crossed
        for frame in pairs(_pcActive) do
            if
                frame._isItemPresetFrame
                and frame._presetItemID
                and not frame._displayItemID
                and frame._cachedTotal
                and frame._cachedTotal > 0
                and frame._countArm == false
            then
                local old, num = frame._cachedTotal, mod._ReadItemPresetCount(frame)
                if num ~= old then
                    frame._countArm = true
                    hit = true
                    if (num == 0) ~= (old == 0) then crossed = true end
                end
            end
        end
        if hit then
            _presetCdDirty = true
            _pcAllSettled = false
            -- Fast lane like a cast: the new count lands after the cast's own pass, inside the 1 Hz cap.
            mod._pcLast = 0
            if mod.ArmBuffTicker then mod.ArmBuffTicker() end
            if crossed then CheckItemPresenceForHide() end
        end
        -- THE item-cooldown edge: fires when any item cooldown starts, ends
        -- early or is modified. Re-walk the item chains on the next pass;
        -- between these edges the cached start/dur drives the display.
        -- (Live set: hidden frames re-arm on their Show edge.)
        -- SETTLED-GATED (measured 2026-08-16: this event fires ~0.7 Hz
        -- ambiently at idle with nothing cooling, and was the drain's -- and
        -- the buff ticker's -- dominant wake source): with every preset
        -- settled there is no running item cd to end or modify, and an item
        -- cd can only START via edges that own UNGATED lanes (player cast,
        -- bag content, equipment, encounter reset), so ambient chatter has
        -- nothing to report. The count recheck above stays ungated on purpose:
        -- it is the only charge-only count refresh and arms only on a change.
        if not _pcAllSettled then
            for frame in pairs(_pcActive) do
                if frame._isItemPresetFrame then frame._itemWalkArm = true end
            end
            _presetCdDirty = true
            if mod.ArmBuffTicker then mod.ArmBuffTicker() end
        end
        return
    end
    if evt == "ENCOUNTER_END" or evt == "CHALLENGE_MODE_START" then
        if evt == "CHALLENGE_MODE_START" or select(2, GetInstanceInfo()) == "raid" then
            for _, frame in pairs(_presetFrames) do
                if frame._isItemPresetFrame then
                    frame._cdStart = nil
                    frame._cdDur = nil
                    frame._inCombatLockout = nil
                    if frame._cooldown then frame._cooldown:Clear() end
                    if frame._tex then frame._tex:SetDesaturated(false) end
                    frame._lastDesat = false
                    frame._itemWalkArm = true
                end
            end
            _encounterResetUntil = GetTime() + 3
            _pcAllSettled = false
        end
        return
    end
    if evt == "UNIT_SPELLCAST_SUCCEEDED" and a1 == "player" then
        local spellId = a3
        -- Fast lane: a player cast is the moment a preset cooldown can START, so it
        -- arms the drain AND resets its rate cap -- the swipe appears on the next tick.
        -- Pure SPELL_UPDATE_COOLDOWN noise (the catch-all below) coasts on the 1 Hz
        -- slow lane instead. Item presets re-walk (combat pots show instantly, ahead
        -- of BAG_UPDATE_COOLDOWN). Spell presets are deliberately NOT armed here:
        -- pushes exclude the GCD by construction (duration fetch passes ignoreGCD),
        -- so a cast pushes nothing visible on a ready frame, and the cast's OWN
        -- cooldown start arrives as a named SPELL_UPDATE_COOLDOWN in the same
        -- cascade, which the catch-all's payload discrimination arms precisely.
        for frame in pairs(_pcActive) do
            if frame._isItemPresetFrame then
                frame._itemWalkArm = true
                frame._countArm = true
            end
        end
        _presetCdDirty = true
        _pcAllSettled = false
        mod._pcLast = 0
        if mod.ArmBuffTicker then mod.ArmBuffTicker() end
        local targetItemID = spellId and _combatLockoutSpells[spellId]
        if targetItemID and InCombatLockdown() then
            for _, frame in pairs(_presetFrames) do
                if frame._isItemPresetFrame and frame._presetItemID == targetItemID then
                    frame._inCombatLockout = true
                    if frame._cooldown then frame._cooldown:Clear() end
                    if frame._tex then frame._tex:SetDesaturated(true) end
                    frame._lastDesat = true
                end
            end
        end
        return
    end
    if evt == "PLAYER_REGEN_ENABLED" then
        for _, frame in pairs(_presetFrames) do
            if frame._isItemPresetFrame then
                if frame._inCombatLockout then frame._inCombatLockout = nil end
                frame._itemWalkArm = true
            end
        end
        _presetCdDirty = true -- refresh desaturation on combat end
        _pcAllSettled = false
        if mod.ArmBuffTicker then mod.ArmBuffTicker() end
        return
    end
    if evt == "SPELL_UPDATE_USABLE" then
        -- Resource-tint edge: arm a READ of the custom-spell frames so the usability
        -- tint reacts without keeping ready frames in the poll. Same settled gate as
        -- the catch-all (today's contract: no drain work while settled), plus a 0.2s
        -- arm cap so usability churn can never re-arm passes beyond ~5/s.
        if not _pcAllSettled then
            local nowU = GetTime()
            if nowU >= (mod._pcUsableNext or 0) then
                mod._pcUsableNext = nowU + 0.2
                for frame in pairs(_pcActive) do
                    if frame._isCustomSpellFrame then frame._cdEvalArm = true end
                end
                _presetCdDirty = true
                if mod.ArmBuffTicker then mod.ArmBuffTicker() end
            end
        end
        return
    end
    -- High-frequency events: arm the drain ONLY while something is in flight.
    -- When the last pass found every preset frame settled, this noise
    -- (SPELL_UPDATE_COOLDOWN/CHARGES fire steadily even at idle) would only
    -- schedule identical repaints -- every real settled->unsettled transition
    -- comes through the fast lanes above.
    if not _pcAllSettled then
        if evt == "SPELL_UPDATE_COOLDOWN" then
            -- Payload discrimination (verified on both clients): a NAMED event
            -- re-arms the duration-object push only for the matching spell presets
            -- (id or base id -- CDR on a transform ticks the override, whose base id
            -- matches the tracked spell). A nil or unreadable id is a wave ("all
            -- cooldowns should be updated") and re-arms every spell preset. Frames
            -- with no extracted id yet arm conservatively.
            local spellRef, base = a1, a2
            local named = _PlainNum(spellRef)
            local baseOk = named and _PlainNum(base)
            for frame in pairs(_pcActive) do
                if not frame._isItemPresetFrame then
                    local fsid = frame._cachedPresetSID
                    if not named or not fsid or fsid == spellRef or (baseOk and fsid == base) then
                        frame._cdPushArm = true
                    end
                end
            end
        elseif evt == "SPELL_UPDATE_CHARGES" then
            -- Same discrimination for charge movement (charge customs).
            local spellRef = a1
            local named = _PlainNum(spellRef)
            for frame in pairs(_pcActive) do
                if not frame._isItemPresetFrame then
                    local fsid = frame._cachedPresetSID
                    if not named or not fsid or fsid == spellRef then frame._cdPushArm = true end
                end
            end
        end
        _presetCdDirty = true
        if mod.ArmBuffTicker then mod.ArmBuffTicker() end
    elseif evt == "SPELL_UPDATE_CHARGES" and mod._cdmAnyCustomForceCount then
        -- Settled-state charge wake, shown charge texts ONLY: a charge regen
        -- completing is the one count edge that arrives with no cast and no
        -- unsettled state (a SPEND always rides a cast, which unsettles and
        -- lets the named lane above arm precisely). Named ids wake just the
        -- matching text; unreadable ids (instanced secrecy) wake every shown
        -- text, capped at one arm per 0.2s so charge chatter can never hold
        -- the settled drain awake.
        local nowC = GetTime()
        if nowC >= (mod._pcChargeNext or 0) then
            local spellRef = a1
            local named = _PlainNum(spellRef)
            local hit
            for frame in pairs(_pcActive) do
                if
                    frame._isCustomSpellFrame
                    and frame._castCountText
                    and frame._castCountText:IsShown()
                    and (not named or not frame._cachedPresetSID or frame._cachedPresetSID == spellRef)
                then
                    frame._cdEvalArm = true
                    hit = true
                end
            end
            if hit then
                mod._pcChargeNext = nowC + 0.2
                _presetCdDirty = true
                if mod.ArmBuffTicker then mod.ArmBuffTicker() end
            end
        end
    end
end)

-- Custom aura bar cast detection
local _pendingCastIDs = {}
-- Cast-timer state for custom/preset buffs, keyed "barKey:spellID". Declared
-- here (before CollectAndReanchor) so the buff-phase own-frame injection can
-- read the live timer to decide which custom buffs to render.
local _customAuraTimers = {}
local _customBuffDirty = false
local _customBuffFrame = CreateFrame("Frame")
_customBuffFrame:Hide()
local CUSTOM_BUFF_THROTTLE = 0.05
local _lastCustomBuffTime = 0
_customBuffFrame:SetScript("OnUpdate", function(self)
    if not _customBuffDirty then
        self:Hide()
        return
    end
    local nowTime = GetTime()
    if nowTime - _lastCustomBuffTime < CUSTOM_BUFF_THROTTLE then return end
    _customBuffDirty = false
    _lastCustomBuffTime = nowTime
    if mod.UpdateCustomBuffBars then mod.UpdateCustomBuffBars() end
end)

local function QueueCustomBuffs()
    _customBuffDirty = true
    _customBuffFrame:Show()
end
mod.QueueCustomBuffUpdate = QueueCustomBuffs

-- Bloodlust on a Custom Auras (icon) bar reuses the potion-preset machinery:
-- the Sated-debuff rising edge (detected in CUI_CDM_BuffBarPresets.lua) emulates a "cast" of
-- the lust buff, so the existing self-timed icon + reverse swipe renders it with
-- no duplicate display code. Both faction IDs are flagged so a profile shared
-- across factions still resolves (only the bar's own ID is actually tracked).
local LUST_PRESET_SPELLS = { [2825] = true, [32182] = true }
mod.IsLustPresetSpell = function(spellRef) return LUST_PRESET_SPELLS[spellRef] == true end

-- Called from the lust listener's rising edge: mark the lust buff as "just cast"
-- so UpdateCustomBuffBars starts its 40s self-timed icon. A no-op for any bar not
-- tracking it (the pending flag is wiped each pass).
function mod.SignalLustCast()
    _pendingCastIDs[2825] = true
    _pendingCastIDs[32182] = true
    QueueCustomBuffs()
end

-- True if any enabled Custom Auras (custom_buff) bar tracks the lust buff, so the
-- shared lust-buff listener stays armed even with no Tracking Bar lust bar present.
function mod.AnyCustomAuraLust()
    local profile = ECME and ECME.db and ECME.db.profile
    if not (profile and profile.cdmBars and profile.cdmBars.bars) then return false end
    for _, edge in ipairs(profile.cdmBars.bars) do
        if edge.enabled and (edge.barType == "custom_buff" or edge.barType == "buffs") then
            local sd = mod.GetBarSpellData and mod.GetBarSpellData(edge.key)
            if sd and sd.assignedSpells then
                for _, spellRef in ipairs(sd.assignedSpells) do
                    if LUST_PRESET_SPELLS[spellRef] then return true end
                end
            end
        end
    end
    return false
end

-- Time Spiral "Free Move" preset: same emulated-cast trick as Bloodlust. The
-- glow-armed rising edge (CUI_CDM_BuffBarPresets.lua _ensureTimeSpiralListener) calls this to
-- mark spell 374968 as "just cast" so the existing self-timed-icon path renders
-- a 10s Custom Auras (icon) display. A no-op for any bar not tracking it.
function mod.SignalTimeSpiralCast()
    _pendingCastIDs[374968] = true
    QueueCustomBuffs()
end

-- Called from the Time Spiral glow-HIDE edge (proc consumed): expire any active
-- 374968 Custom Auras (icon) window now so the icon disappears with the glow
-- instead of riding out the full 10s. Clears every "barKey:374968" timer (the
-- suffix uniquely identifies the spell on any bar), then queues a refresh:
-- custom_buff bars hide their own-frame on the update, buff bars drop the
-- injected frame on the reanchor.
function mod.SignalTimeSpiralEnd()
    local suffix = ":374968"
    local num = #suffix
    local any = false
    for key in pairs(_customAuraTimers) do
        if type(key) == "string" and key:sub(-num) == suffix then
            _customAuraTimers[key] = nil
            any = true
        end
    end
    if any then
        QueueCustomBuffs()
        if mod.QueueReanchor then mod.QueueReanchor() end
    end
end

-- True if any enabled Custom Auras (custom_buff) / buff bar tracks Time Spiral,
-- so the shared glow listener stays armed even with no Tracking Bar present.
function mod.AnyCustomAuraTimeSpiral()
    local profile = ECME and ECME.db and ECME.db.profile
    if not (profile and profile.cdmBars and profile.cdmBars.bars) then return false end
    for _, edge in ipairs(profile.cdmBars.bars) do
        if edge.enabled and (edge.barType == "custom_buff" or edge.barType == "buffs") then
            local sd = mod.GetBarSpellData and mod.GetBarSpellData(edge.key)
            if sd and sd.assignedSpells then
                for _, spellRef in ipairs(sd.assignedSpells) do
                    if spellRef == 374968 then return true end
                end
            end
        end
    end
    return false
end

local _spellCastListener = CreateFrame("Frame")
_spellCastListener:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
_spellCastListener:SetScript("OnEvent", function(_, _, _, _, spellId)
    if spellId then
        _pendingCastIDs[spellId] = true
        QueueCustomBuffs()
    end
end)

Inner._customAuraTimers, Inner._pendingCastIDs = _customAuraTimers, _pendingCastIDs
Inner.ApplyPresetGCDSwipe, Inner.PotSwap = ApplyPresetGCDSwipe, PotSwap
Inner.ProcessPresetCooldowns = ProcessPresetCooldowns
Inner.QueueCustomBuffUpdate = QueueCustomBuffs
Inner.broken = false
