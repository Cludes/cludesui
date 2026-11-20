if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUICdmBarGlows.lua
--  Bar Glows: Overlays glow effects on action bar / CDM bar buttons when
--  configured buff/aura spells become active (or inactive in MISSING mode).
--  v4: CDM bar assignments keyed by cooldownID for stability across reanchors.
-------------------------------------------------------------------------------
local ADDON_NAME, mod = ...

-- Glow functions from CUI_CDM_Glows.lua (available after it loads)
local StartNativeGlow = function(...)
    if mod.StartNativeGlow then
        return mod.StartNativeGlow(...)
    end
end
local StopNativeGlow = function(...)
    if mod.StopNativeGlow then
        return mod.StopNativeGlow(...)
    end
end

-- Slot offsets per bar index (matches CludesUIActionBars BAR_SLOT_OFFSETS)
local BAR_OFFSETS = { 0, 60, 48, 24, 36, 144, 156, 168 }

-------------------------------------------------------------------------------
--  Button Lookup
-------------------------------------------------------------------------------

-- Action bar button lookup (stable slot-based)
local function GetActionBarButton(barIdx, btnIdx)
    local off = BAR_OFFSETS[barIdx] or 0
    local slot = off + btnIdx
    local button = _G["EABButton" .. slot]
    if button then
        return button
    end
    local BLIZZ_PREFIXES = {
        "ActionButton",
        "MultiBarBottomLeftButton",
        "MultiBarBottomRightButton",
        "MultiBarRightButton",
        "MultiBarLeftButton",
        "MultiBar5Button",
        "MultiBar6Button",
        "MultiBar7Button",
    }
    if barIdx >= 1 and barIdx <= #BLIZZ_PREFIXES then
        button = _G[BLIZZ_PREFIXES[barIdx] .. btnIdx]
    end
    return button
end

-- CDM bar icon lookup by cooldownID (stable across reanchors).
-- Walks all CDM bars (default + extras) since the 1-spell-per-bar invariant
-- guarantees a cooldownID can only live on one bar at a time.
local function FindCDMButtonByCooldownID(cooldownID)
    if not mod.cdmBarIcons then
        return nil
    end
    for _, icons in pairs(mod.cdmBarIcons) do
        for index = 1, #icons do
            local iconTex = icons[index]
            if iconTex and iconTex.cooldownID == cooldownID then
                return iconTex
            end
        end
    end
    return nil
end

-------------------------------------------------------------------------------
--  Data Access
-------------------------------------------------------------------------------

--- Get barGlows data from SavedVariables (with lazy init)
function mod.GetBarGlows()
    local specKey = mod.GetActiveSpecKey and mod.GetActiveSpecKey()
    if not specKey then
        return { enabled = true, selectedBar = "cooldowns", assignments = {} }
    end
    -- Bar glows are spec-specific and per-profile: specProfiles[specKey].barGlows
    -- under the active profile's bucket (ns.GetActiveSpecProfiles).
    local sp = mod.GetActiveSpecProfiles and mod.GetActiveSpecProfiles()
    if not sp then
        return { enabled = true, selectedBar = "cooldowns", assignments = {} }
    end
    if not sp[specKey] then
        sp[specKey] = { barSpells = {} }
    end
    local prof = sp[specKey]
    if not prof.barGlows or not next(prof.barGlows) then
        prof.barGlows = {
            enabled = true,
            selectedBar = "cooldowns",
            assignments = {},
        }
    end
    -- Live migration: colorMode replaced classColor + "glowColor set" nil check
    if not prof.barGlows._colorModeMigrated then
        prof.barGlows._colorModeMigrated = true
        for _, buffList in pairs(prof.barGlows.assignments) do
            for _, record in ipairs(buffList) do
                if not record.colorMode then
                    if record.classColor then
                        record.colorMode = "class"
                    elseif record.glowColor then
                        record.colorMode = "custom"
                    else
                        record.colorMode = "default"
                    end
                end
            end
        end
    end
    return prof.barGlows
end

--- Collect all tracked buff spells across all CDM buff bars
--- Returns tracked (displayed in CDM) and untracked (known but not displayed)
function mod.GetAllCDMBuffSpells()
    local ECME = mod.ECME
    if not ECME or not ECME.db then
        return {}, {}
    end
    local profile = ECME.db.profile
    if not profile or not profile.cdmBars or not profile.cdmBars.bars then
        return {}, {}
    end

    local trackedSet = {}
    local trackedOrder = {}

    for _, barFrame in ipairs(profile.cdmBars.bars) do
        if mod.IsBarBuffFamily(barFrame) then
            local spells = mod.GetCDMSpellsForBar and mod.GetCDMSpellsForBar(barFrame.key)
            if spells then
                for _, sp in ipairs(spells) do
                    if sp.isKnown and sp.spellID and sp.spellID > 0 and not trackedSet[sp.spellID] then
                        local record = {
                            spellID = sp.spellID,
                            cdID = sp.cdID,
                            name = sp.name,
                            icon = sp.icon,
                            barKey = barFrame.key,
                            barName = barFrame.name or barFrame.key,
                        }
                        trackedSet[sp.spellID] = record
                        trackedOrder[#trackedOrder + 1] = record
                    end
                end
            end
        end
    end

    local IsInViewer = mod.IsSpellInBuffBarViewer
    local tracked, untracked = {}, {}
    for _, record in ipairs(trackedOrder) do
        local spellRef = record.spellID
        if spellRef and IsInViewer and IsInViewer(spellRef) then
            tracked[#tracked + 1] = record
        else
            untracked[#untracked + 1] = record
        end
    end

    return tracked, untracked
end

-------------------------------------------------------------------------------
--  Overlay System
-------------------------------------------------------------------------------
local overlayFrames = {} -- [key] = overlay frame
local lastStates = {} -- [key] = bool (last glow state for change detection)
local _cachedBG = nil -- cached barGlows reference (refreshed on SetupOverlays)

-------------------------------------------------------------------------------
--  Stack-threshold gate (secret-safe)
--  Applications counts read SECRET even in open-world content, so the
--  threshold compare can never happen in Lua (a hard error on a secret).
--  Same trick -- and same 5-operator support -- as the per-icon Glow at
--  Stacks feature (CludesUICdmHooks.lua's StackGlow_Configure/Feed):
--  one-unit StatusBar windows perform lower/upper bounds C-side via
--  SetValue; equality intersects one of each (two gates). A fixed-size
--  CLAMPTOBLACKADDITIVE mask rides each gate's fill edge and is handed to
--  StartNativeGlow so the glow texture itself is cropped by the fill(s) --
--  Lua never reads the count, just forwards it.
-------------------------------------------------------------------------------
local stackGates = {} -- [key] = { gate,mask,fill, gate2,mask2,fill2, pad, threshold, operator, closeValue, openValue, closeValue2 }

local function StackGateSize(overlayFrame)
    local wid, hgt = overlayFrame:GetWidth(), overlayFrame:GetHeight()
    if not wid or wid < 5 then
        wid = 36
    end
    if not hgt or hgt < 5 then
        hgt = wid
    end
    return wid, hgt
end

local function NewStackGate(overlayFrame, pad)
    local gate = CreateFrame("StatusBar", nil, overlayFrame)
    gate:SetPoint("TOPLEFT", overlayFrame, "TOPLEFT", -pad, pad)
    gate:SetPoint("BOTTOMRIGHT", overlayFrame, "BOTTOMRIGHT", pad, -pad)
    gate:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    local fillTex = gate:GetStatusBarTexture()
    if fillTex then
        fillTex:SetAlpha(0)
    end
    gate:EnableMouse(false)
    local mask = gate:CreateMaskTexture()
    mask:SetTexture("Interface\\Buttons\\WHITE8x8", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
    return gate, mask, fillTex
end

local function SizeStackGateMasks(st, width, height)
    local wid, hgt = width + st.pad * 2, height + st.pad * 2
    st.mask:SetSize(wid, hgt)
    if st.mask2 then
        st.mask2:SetSize(wid, hgt)
    end
end

local function StackGlowMatches(value, operator, threshold)
    if operator == "lt" then
        return value < threshold
    end
    if operator == "lte" then
        return value <= threshold
    end
    if operator == "eq" then
        return value == threshold
    end
    if operator == "gt" then
        return value > threshold
    end
    return value >= threshold
end

local function EnsureStackGate(overlayFrame, key)
    local st = stackGates[key]
    if not st then
        st = {}
        stackGates[key] = st
        local wid, hgt = StackGateSize(overlayFrame)
        local pad = math.ceil(math.max(wid, hgt) * 0.4)
        if pad < 12 then
            pad = 12
        end
        st.pad = pad
        st.gate, st.mask, st.fill = NewStackGate(overlayFrame, pad)
        SizeStackGateMasks(st, wid, hgt)
    end
    return st
end

-- (Re)configure the gate(s) for the current threshold/operator. Mirrors
-- StackGlow_Configure's edge math exactly: lower bounds park the mask left
-- and open at max; upper bounds open at min and park right; equality
-- intersects one lower + one upper gate (both masks applied to the glow).
local function ConfigureStackGate(overlayFrame, key, threshold, operator)
    local st = EnsureStackGate(overlayFrame, key)
    if st.threshold == threshold and st.operator == operator then
        return st
    end
    st.threshold, st.operator = threshold, operator

    local max = operator == "lt" or operator == "lte"
    local edge = (operator == "gt" or operator == "lte") and threshold + 1 or threshold
    st.gate:SetMinMaxValues(edge - 1, edge)
    st.mask:ClearAllPoints()
    st.mask:SetPoint(max and "LEFT" or "RIGHT", st.fill or st.gate, "RIGHT", 0, 0)
    st.closeValue = max and edge or edge - 1
    st.openValue = max and edge - 1 or edge

    if operator == "eq" and not st.gate2 then
        local wid, hgt = StackGateSize(overlayFrame)
        st.gate2, st.mask2, st.fill2 = NewStackGate(overlayFrame, st.pad)
        SizeStackGateMasks(st, wid, hgt)
    end
    if st.gate2 then
        local equality = operator == "eq"
        st.gate2:SetMinMaxValues(equality and threshold or 0, equality and threshold + 1 or 1)
        st.mask2:ClearAllPoints()
        st.mask2:SetPoint(equality and "LEFT" or "RIGHT", st.fill2 or st.gate2, "RIGHT", 0, 0)
        st.closeValue2 = equality and threshold + 1 or 0
    end
    return st
end

-- Whether a Cooldown Manager entry names one of the glow spells (its spell,
-- override or a linked spell).
local function EntryHasSid(details, sids)
    if sids[details.spellID] or (details.overrideSpellID and sids[details.overrideSpellID]) then
        return true
    end
    local linked = details.linkedSpellIDs
    if linked then
        for index = 1, #linked do
            if sids[linked[index]] then
                return true
            end
        end
    end
    return false
end

-- Whether a Cooldown Manager entry tracks an aura on another unit.
-- selfAura == false covers spells whose own aura lands elsewhere (Polymorph,
-- Frost Nova, ...). A talent entry that tracks a debuff it applies still reads
-- selfAura == true (Frost Mage's Shatter tracks its linked Freezing debuff on
-- the target), so a harmful linked spell counts as well.
local function EntryOnOtherUnit(details, harmful)
    if details.selfAura == false then
        return true
    end
    local linked = details.linkedSpellIDs
    if harmful and linked then
        for index = 1, #linked do
            if linked[index] and harmful(linked[index]) then
                return true
            end
        end
    end
    return false
end

-- Whether any of the glow spells (sids: set of spellIDs) is tracked on another
-- unit (a target debuff such as Freezing). Only then does the buff ticker need
-- the target UNIT_AURA listener (CludesUICdmHooks): every target aura change
-- rebuilds the active-aura cache, so on a raid boss the whole raid's aura
-- churn would otherwise cost players whose glows only watch their own buffs.
-- Walks the Tracked Buff / Tracked Bar category sets; called from
-- SetupOverlays only (glow rebuilds), never per tick.
local function AnyTargetAura(sids)
    if not next(sids) then
        return false
    end
    local CV = C_CooldownViewer
    local cats = Enum and Enum.CooldownViewerCategory
    if not (cats and CV and CV.GetCooldownViewerCategorySet and CV.GetCooldownViewerCooldownInfo) then
        return false
    end
    local harmful = C_Spell and C_Spell.IsSpellHarmful
    for _, category in ipairs({ cats.TrackedBuff, cats.TrackedBar }) do
        local success, cdIDs = pcall(CV.GetCooldownViewerCategorySet, category, true)
        if success and type(cdIDs) == "table" then
            for _, cdID in ipairs(cdIDs) do
                local details = CV.GetCooldownViewerCooldownInfo(cdID)
                if details and EntryHasSid(details, sids) and EntryOnOtherUnit(details, harmful) then
                    return true
                end
            end
        end
    end
    return false
end

-------------------------------------------------------------------------------
--  Glow When Usable (entry.mode == "USABLE"): the glow runs while the button's
--  own ability could be pressed, the same test as the Cooldown State Effect
--  Hidden Until Usable: off cooldown (the GCD does not count) and usable for any
--  reason but missing power, so reactive abilities (Overpower, Revenge, Execute)
--  light up on their proc. The buff ticker is dirty-gated and stops itself, so
--  these glows carry their own edges: SPELL_UPDATE_USABLE (procs),
--  SPELL_UPDATE_COOLDOWN / SPELL_UPDATE_CHARGES (cooldown start and end),
--  registered only while such an entry exists and folded into one pass on the
--  next frame. A changed button ability rebinds through the ability-key path.
-------------------------------------------------------------------------------
-- The spell on a button: a CDM icon's own spell, or what the action slot holds
-- right now (a macro counts through its spell; items and empty slots are nil).
local function RawButtonSpell(button)
    local fc = mod._ecmeFC and mod._ecmeFC[button]
    local spellRef
    if fc then
        spellRef = fc.spellID
    else
        local slot = button.GetAttribute and button:GetAttribute("action") or button.action
        if slot and mod.SlotSpellID then
            -- The assisted-combat button shows whatever is suggested, not an ability of its own.
            local _, _, subType = GetActionInfo(slot)
            if subType ~= "assistedcombat" then
                spellRef = mod.SlotSpellID(slot)
            end
        end
    end
    if type(spellRef) ~= "number" or issecretvalue(spellRef) or spellRef <= 0 then
        return nil
    end
    return spellRef
end

local function BaseSpell(spellRef)
    return C_Spell.GetBaseSpell(spellRef) or spellRef
end

local function LiveSpell(spellRef)
    return C_SpellBook.FindSpellOverrideByID(spellRef) or spellRef
end

-- Glows on an action bar button are saved per ability ("spell_<base spellID>"),
-- so a stance or form swap that repages the bar never moves a glow onto the
-- new ability. Items and empty slots have no ability: positional key instead.
function mod.BarGlowAbilityKey(button)
    local spellRef = button and RawButtonSpell(button)
    return spellRef and ("spell_" .. BaseSpell(spellRef)) or nil
end

local function ButtonSpellID(button)
    local spellRef = RawButtonSpell(button)
    return spellRef and LiveSpell(spellRef)
end
-- Options: the ability a CDM icon's Glow When Usable tests ("cdm_" glows save none).
mod.BarGlowButtonSpell = ButtonSpellID

local UpdateOverlayVisuals -- forward: defined below
local usableEventsOn = false
local usableFlush, usableEvents -- built on the first Glow When Usable entry

-- Blizzard only guarantees GetSpellCooldown's isOnGCD inside the cooldown event itself:
-- a frame later, at the end of a GCD, it reads as a real cooldown for ~0.25s. So whether
-- each USABLE spell is on a real cooldown is worked out in the SPELL_UPDATE_COOLDOWN /
-- CHARGES handler and kept here; the next-frame flush and the buff ticker read the kept
-- answer. A spell not yet seen is read once, outside an event, and kept until the next one.
local usableOnCD = {} -- [live spellID] = true when on a real cooldown
local function ReadRealCooldown(spellRef)
    local details = C_Spell.GetSpellCooldown(spellRef)
    return (details and details.isActive and not details.isOnGCD) or false
end

local function UsableSpellOf(overlayFrame)
    return overlayFrame._abilitySid and LiveSpell(overlayFrame._abilitySid)
        or ButtonSpellID(overlayFrame:GetParent())
end

-- Re-read every tracked USABLE spell; called from the cooldown event handler.
local function RefreshUsableCooldowns()
    wipe(usableOnCD)
    for _, overlayFrame in pairs(overlayFrames) do
        if
            overlayFrame:IsShown()
            and overlayFrame._assignEntry
            and overlayFrame._assignEntry.mode == "USABLE"
        then
            local spellRef = UsableSpellOf(overlayFrame)
            if spellRef and usableOnCD[spellRef] == nil then
                usableOnCD[spellRef] = ReadRealCooldown(spellRef)
            end
        end
    end
end

-- The icon Hidden Until Usable shows: off cooldown (the GCD does not count) and usable.
local function UsablePressable(spellRef)
    local onCD = usableOnCD[spellRef]
    if onCD == nil then
        onCD = ReadRealCooldown(spellRef)
        usableOnCD[spellRef] = onCD
    elseif onCD then
        -- isActive can be trusted outside the event (only isOnGCD cannot): a
        -- cooldown that has ended reads inactive, so the glow comes back without
        -- waiting for the next cooldown event.
        local details = C_Spell.GetSpellCooldown(spellRef)
        if not (details and details.isActive) then
            onCD = false
            usableOnCD[spellRef] = false
        end
    end
    return not onCD and not mod.CdmSpellNotUsable(spellRef)
end

local function SyncUsableEvents(on)
    if on == usableEventsOn then
        return
    end
    usableEventsOn = on
    if on then
        if not usableEvents then
            usableFlush = mod.TakeShell()
            usableFlush:Hide()
            usableFlush:SetScript("OnUpdate", function(self)
                self:Hide()
                if UpdateOverlayVisuals then
                    UpdateOverlayVisuals()
                end
            end)
            usableEvents = mod.TakeShell()
            usableEvents:SetScript("OnEvent", function(_, evt)
                if evt ~= "SPELL_UPDATE_USABLE" then
                    RefreshUsableCooldowns()
                end
                usableFlush:Show()
            end)
        end
        usableEvents:RegisterEvent("SPELL_UPDATE_USABLE")
        usableEvents:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        usableEvents:RegisterEvent("SPELL_UPDATE_CHARGES")
    elseif usableEvents then
        usableEvents:UnregisterAllEvents()
        usableFlush:Hide()
        wipe(usableOnCD)
    end
end

-- Existing position keys ("<bar>_<button>") become ability keys once per spec,
-- by the ability saved with each entry. An entry saved before actionSpellID
-- existed stays on its position key: the button's ability right now (a form or
-- stance may have repaged the bar) could be the wrong one, and the move deletes
-- the old key.
local function MigrateAbilityKeys(backdrop)
    if backdrop._abilityKeysMigrated or not IsLoggedIn() or not GetActionBarButton(1, 1) then
        return
    end
    backdrop._abilityKeysMigrated = true
    local moves -- { { oldKey, newKey, entry }, ... }
    for key, entries in pairs(backdrop.assignments) do
        local barIdx, btnIdx = key:match("^(%d+)_(%d+)$")
        barIdx, btnIdx = tonumber(barIdx), tonumber(btnIdx)
        if barIdx and btnIdx and barIdx <= #BAR_OFFSETS and type(entries) == "table" then
            for _, entry in ipairs(entries) do
                local spellRef = tonumber(entry.actionSpellID)
                if spellRef and spellRef > 0 then
                    moves = moves or {}
                    moves[#moves + 1] = { key, "spell_" .. BaseSpell(spellRef), entry }
                end
            end
        end
    end
    if not moves then
        return
    end
    for _, m in ipairs(moves) do
        local old, new, e = m[1], m[2], m[3]
        local dst = backdrop.assignments[new]
        if not dst then
            dst = {}
            backdrop.assignments[new] = dst
        end
        dst[#dst + 1] = e
        local source = backdrop.assignments[old]
        for index = #source, 1, -1 do
            if source[index] == e then
                table.remove(source, index)
                break
            end
        end
        if #source == 0 then
            backdrop.assignments[old] = nil
        end
    end
end

-- The action buttons currently showing each ability: base spellID -> { {btn, tag}, ... }.
-- Every table is reused by the next scan (it runs on each form shift or bar change):
-- the target record and its tag are built once per button, the lists wiped and refilled.
local scanMap = {}
local scanTargets = {} -- [btn] = { btn =, tag = }
local slotBase = {} -- [action slot] = base spellID the last scan found there
local glowedAbilities = {} -- base spellIDs a "spell_<id>" glow is saved for (last BindOverlays)

local function ScanActionButtons()
    for _, t in pairs(scanMap) do
        wipe(t)
    end
    wipe(slotBase)
    for barIdx = 1, #BAR_OFFSETS do
        for btnIdx = 1, 12 do
            local button = GetActionBarButton(barIdx, btnIdx)
            local spellRef = button and RawButtonSpell(button)
            if spellRef then
                local base = BaseSpell(spellRef)
                local t = scanMap[base]
                if not t then
                    t = {}
                    scanMap[base] = t
                end
                local target = scanTargets[button]
                if not target then
                    target = { btn = button, tag = "b" .. barIdx .. "x" .. btnIdx }
                    scanTargets[button] = target
                end
                t[#t + 1] = target
                local slot = button.GetAttribute and button:GetAttribute("action") or button.action
                if slot then
                    slotBase[slot] = base
                end
            end
        end
    end
    return scanMap
end

-- Create / re-parent one overlay per glow entry on every button it applies to,
-- hide the rest. Returns what the full setup needs to know about the glows.
local function BindOverlays(backdrop)
    local stackSids
    local glowSids = {} -- every assigned glow's spellID, for AnyTargetAura
    local anyHero, anyUsable, anySpellKey
    local abilityButtons -- ScanActionButtons(), built on the first ability key
    wipe(glowedAbilities)

    local activeKeys = {}
    for assignKey, buffList in pairs(backdrop.assignments) do
        if buffList and #buffList > 0 then
            local targets -- { { btn =, tag = }, ... }
            local abilitySid

            local cdID = assignKey:match("^cdm_(%d+)$")
            local spellKey = assignKey:match("^spell_(%d+)$")
            if cdID then
                -- CDM bar assignment: "cdm_<cooldownID>"
                local button = FindCDMButtonByCooldownID(tonumber(cdID))
                targets = button and { { btn = button } }
            elseif spellKey then
                -- Action bar ability: "spell_<base spellID>"
                anySpellKey = true
                abilitySid = tonumber(spellKey)
                glowedAbilities[abilitySid] = true
                abilityButtons = abilityButtons or ScanActionButtons()
                targets = abilityButtons[abilitySid]
            else
                -- Action bar position (items, empty slots): "<barIdx>_<btnIdx>"
                local barIdx, btnIdx = assignKey:match("^(%d+)_(%d+)$")
                barIdx = tonumber(barIdx)
                btnIdx = tonumber(btnIdx)
                local button = barIdx and btnIdx and GetActionBarButton(barIdx, btnIdx)
                targets = button and { { btn = button } }
            end

            if targets then
                for _, target in ipairs(targets) do
                    local button = target.btn
                    for index, record in ipairs(buffList) do
                        local key = assignKey .. "_" .. index .. (target.tag and ("_" .. target.tag) or "")
                        local overlayFrame = overlayFrames[key]
                        if not overlayFrame then
                            overlayFrame = CreateFrame("Frame", "ECME_Glow_" .. key, button)
                            overlayFrames[key] = overlayFrame
                        end
                        if overlayFrame:GetParent() ~= button then
                            -- A running glow stays on its old button otherwise.
                            StopNativeGlow(overlayFrame)
                            lastStates[key] = nil
                            overlayFrame:SetParent(button)
                        end
                        overlayFrame:SetAllPoints(button)
                        overlayFrame:SetFrameLevel(button:GetFrameLevel() + 15)
                        overlayFrame:SetAlpha(1)
                        overlayFrame._assignEntry = record
                        overlayFrame._abilitySid = abilitySid
                        overlayFrame:Show()
                        activeKeys[key] = true
                        if record.spellID and record.spellID > 0 then
                            glowSids[record.spellID] = true
                        end
                        -- The And condition's second buff can be a target debuff too.
                        local cond = record.andMode == "and"
                            and type(record.conditions) == "table"
                            and record.conditions[1]
                        local csid = type(cond) == "table" and tonumber(cond.spellID)
                        if csid and csid > 0 then
                            glowSids[csid] = true
                        end
                        if record.heroTree and not CludesUI.IS_FOREVER then
                            anyHero = true
                        end
                        if record.mode == "USABLE" then
                            anyUsable = true
                        end
                        local spellRef = record.stackEnabled and record.spellID
                        if spellRef and spellRef > 0 then
                            stackSids = stackSids or {}
                            stackSids[spellRef] = true
                        end
                    end
                end
            end
        end
    end

    -- Hide overlays that are no longer assigned or whose ability left the bars
    for key, overlayFrame in pairs(overlayFrames) do
        if not activeKeys[key] then
            StopNativeGlow(overlayFrame)
            overlayFrame:Hide()
            lastStates[key] = nil
        end
    end
    return stackSids, glowSids, anyHero, anyUsable, anySpellKey
end

-- Ability-keyed glows follow the bars: a stance or form change, a moved or
-- replaced ability and a spell change rebind them. The CDM event frame
-- (CUI_CDM_Events.lua) already receives those events and calls
-- ns.QueueBarGlowRebind while ns._barGlowRebindOn is set; bursts fold into one
-- pass on the next frame. No events of our own, no frame until first needed.
local rebindFlush
local function SyncRebindEvents(on)
    mod._barGlowRebindOn = on or nil
    if on and not rebindFlush then
        rebindFlush = mod.TakeShell()
        rebindFlush:Hide()
        rebindFlush:SetScript("OnUpdate", function(self)
            self:Hide()
            local backdrop = _cachedBG
            if not backdrop or not backdrop.enabled then
                return
            end
            BindOverlays(backdrop)
            if UpdateOverlayVisuals then
                UpdateOverlayVisuals()
            end
        end)
    elseif not on and rebindFlush then
        rebindFlush:Hide()
    end
end

-- A slot change only matters when the slot holds, or held at the last scan, an ability
-- a glow is saved for (slot is ACTIONBAR_SLOT_CHANGED's payload; 0 or nil = any slot).
-- The slot's new ability is recorded either way so the next change compares against it.
function mod.QueueBarGlowRebind(evt, slot)
    if not rebindFlush then
        return
    end
    if evt == "ACTIONBAR_SLOT_CHANGED" and slot and slot ~= 0 and mod.SlotSpellID then
        local nowTime = mod.SlotSpellID(slot)
        nowTime = type(nowTime) == "number"
                and not issecretvalue(nowTime)
                and nowTime > 0
                and BaseSpell(nowTime)
            or nil
        local was = slotBase[slot]
        slotBase[slot] = nowTime
        if not ((nowTime and glowedAbilities[nowTime]) or (was and glowedAbilities[was])) then
            return
        end
    end
    rebindFlush:Show()
end

--- Rebuild overlay frames from assignments
local function SetupOverlays()
    local backdrop = mod.GetBarGlows()
    _cachedBG = backdrop
    if not backdrop or not backdrop.enabled then
        for key, overlayFrame in pairs(overlayFrames) do
            StopNativeGlow(overlayFrame)
            overlayFrame:Hide()
        end
        mod._barGlowStackSids = nil
        mod._barGlowAnyHero = nil
        SyncUsableEvents(false)
        SyncRebindEvents(false)
        mod._bgWantTargetAuras = false
        if mod.SetBarGlowTargetAuras then
            mod.SetBarGlowTargetAuras(false)
        end
        return
    end

    MigrateAbilityKeys(backdrop)

    -- stackSids: whether the buff-tick's aura pool-walk should bother reading
    -- applications at all (CUI_CDM_HookViewers.lua): the set of spellIDs
    -- stack-gated entries name, nil when there are none. Only frames resolving
    -- to one of these ids pay the applications read; no gated entry = no reads.
    local stackSids, glowSids, anyHero, anyUsable, anySpellKey = BindOverlays(backdrop)
    mod._barGlowStackSids = stackSids
    -- A hero-talent-gated glow exists: talent changes re-run the glow pass.
    mod._barGlowAnyHero = anyHero
    -- A Glow When Usable entry exists: its own cooldown / usability edges listen.
    SyncUsableEvents(anyUsable == true)
    -- An ability-keyed glow exists: bar changes rebind it.
    SyncRebindEvents(anySpellKey == true)
    -- Listen to target auras only while some glow tracks a non-self aura (CludesUICdmHooks).
    local wantTarget = AnyTargetAura(glowSids)
    mod._bgWantTargetAuras = wantTarget
    if mod.SetBarGlowTargetAuras then
        mod.SetBarGlowTargetAuras(wantTarget)
    end

    -- Force re-evaluation on next tick
    wipe(lastStates)
end

--- Update glow visuals based on current aura state.
--- Called each CDM tick (~10Hz from BuffTicker).
UpdateOverlayVisuals = function()
    local backdrop = _cachedBG
    if not backdrop or not backdrop.enabled then
        return
    end

    for key, overlayFrame in pairs(overlayFrames) do
        if overlayFrame:IsShown() and overlayFrame._assignEntry then
            local record = overlayFrame._assignEntry
            local spellId = record.spellID
            local mode = record.mode or "ACTIVE"
            local onlyInCombat = record.onlyInCombat == true

            local auraActive = false
            if spellId and spellId > 0 and mode ~= "USABLE" then
                local cache = mod._tickBlizzActiveCache
                if cache and cache[spellId] then
                    auraActive = true
                end
            end

            local shouldGlow
            if mode == "USABLE" then
                local btnSid = UsableSpellOf(overlayFrame)
                shouldGlow = btnSid ~= nil and UsablePressable(btnSid)
            elseif mode == "MISSING" then
                shouldGlow = not auraActive
            else
                shouldGlow = auraActive
            end
            -- Second-buff (And) and hero talent conditions (CludesUICdmBarGlowConditions.lua)
            if record.andMode or record.heroTree then
                shouldGlow = mod.BarGlowCombine(record, shouldGlow, mod._tickBlizzActiveCache)
            end

            if shouldGlow and onlyInCombat then
                shouldGlow = (InCombatLockdown and InCombatLockdown())
                    or UnitAffectingCombat("player")
                    or false
            end

            -- At Stacks (ACTIVE mode only): fed to the gate(s) every tick
            -- regardless of state-change dedupe below, so the mask tracks a
            -- live stack count while the glow keeps running. A KNOWN count
            -- that fails the comparison stops the glow outright (Lua-side,
            -- cheap); an UNKNOWN/SECRET count never blocks it -- the gate's
            -- open value / the engine-side clamp decide instead.
            local gateSt
            if
                shouldGlow
                and mode ~= "MISSING"
                and mode ~= "USABLE"
                and record.stackEnabled
                and spellId
                and spellId > 0
            then
                local threshold = tonumber(record.stackThreshold) or 2
                local operator = record.stackOperator or "gte"
                gateSt = ConfigureStackGate(overlayFrame, key, threshold, operator)
                -- Same sid/baseSID/linked resolution as auraActive above, so
                -- this matches whatever spellID the entry was saved against
                -- (a raw GetPlayerAuraBySpellID(spellID) query missed on the
                -- override/linked-id drift these tracked buffs can have).
                local stacks = mod._tickBlizzAuraStacks and mod._tickBlizzAuraStacks[spellId]
                -- Secret probe FIRST: any truthy/nil/relational test on a
                -- secret value hard-errors, not just `<`/`>=`.
                local secret = issecretvalue and issecretvalue(stacks)
                local feedValue
                if secret then
                    feedValue = stacks
                elseif stacks == nil then
                    feedValue = gateSt.openValue
                elseif not StackGlowMatches(stacks, operator, threshold) then
                    shouldGlow = false
                else
                    feedValue = stacks
                end
                if shouldGlow then
                    gateSt.gate:SetValue(feedValue)
                    if gateSt.gate2 then
                        -- Explicit branch: an `and feedValue or 1` form would test
                        -- a secret feedValue's truthiness and hard-error.
                        if operator == "eq" then
                            gateSt.gate2:SetValue(feedValue)
                        else
                            gateSt.gate2:SetValue(1)
                        end
                    end
                end
            end

            -- Only update start/stop on state change (avoids restarting animations)
            if shouldGlow ~= lastStates[key] then
                lastStates[key] = shouldGlow
                if shouldGlow then
                    StopNativeGlow(overlayFrame)
                    local style = record.glowStyle or 1
                    -- Force Custom Shape Glow for custom-shaped icons
                    local glowParent = overlayFrame:GetParent()
                    local gpfc = glowParent and mod._ecmeFC and mod._ecmeFC[glowParent]
                    local shapeName = gpfc and gpfc.shapeName
                    if
                        shapeName
                        and shapeName ~= "square"
                        and shapeName ~= "csquare"
                        and shapeName ~= "none"
                    then
                        style = 2
                    end
                    local cr, cg, callback
                    if record.colorMode == "class" then
                        local cc = CludesUI.GetClassColor(CludesUI._playerClass)
                        cr, cg, callback = cc.r, cc.g, cc.b
                    elseif record.colorMode == "custom" and record.glowColor then
                        cr = record.glowColor.r or 1
                        cg = record.glowColor.g or 0.788
                        callback = record.glowColor.b or 0.137
                    end
                    -- Blackout on a CDM icon sits BELOW its cooldown swipe/countdown,
                    -- at the per-icon Blackout's level (+12): under the border (+13)
                    -- and the cooldown widget (+14). An action button's cooldown
                    -- shares the button's own level, so no level lies between its
                    -- icon and its swipe: there the fill takes the normal level like
                    -- every other style and covers the whole button, swipe included.
                    local styleEntry = mod.GLOW_STYLES and mod.GLOW_STYLES[style]
                    local isFill = styleEntry and styleEntry.solidFill
                    overlayFrame:SetFrameLevel(glowParent:GetFrameLevel() + ((isFill and gpfc) and 12 or 15))
                    -- The fill opacity rides opts only for Blackout (fresh table per
                    -- start: the combat-gate record keeps opts by reference).
                    if gateSt then
                        -- Both gate masks travel as data (mask2 is nil unless the
                        -- operator needs the upper gate): the Show Glows Only in
                        -- Combat replay restarts from the recorded opts, so a mask
                        -- bound out here would be missing on every texture that
                        -- replay creates fresh.
                        StartNativeGlow(overlayFrame, style, cr, cg, callback, {
                            maskWith = gateSt.mask,
                            maskWith2 = gateSt.mask2,
                            alpha = isFill and record.glowAlpha or nil,
                        })
                    else
                        StartNativeGlow(
                            overlayFrame,
                            style,
                            cr,
                            cg,
                            callback,
                            isFill and { alpha = record.glowAlpha } or nil
                        )
                    end
                else
                    StopNativeGlow(overlayFrame)
                end
            end
        end
    end
end
mod.UpdateOverlayVisuals = UpdateOverlayVisuals

--- Rebuild overlays and force a visual update
function mod.RequestBarGlowUpdate()
    SetupOverlays()
    UpdateOverlayVisuals()
end
-- Alias for backward compatibility with options code
mod.RequestUpdate = mod.RequestBarGlowUpdate

-------------------------------------------------------------------------------
--  Integration: called from main file's UpdateAllCDMBars tick
-------------------------------------------------------------------------------

-- Called once during CDMFinishSetup
function mod.InitBarGlows()
    SetupOverlays()
end
