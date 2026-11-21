if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_CDM_HookPresetFrames.lua
--
--  Preset and custom frames, out of range coloring, Always Show Buffs
--  placeholders and empty slots.
--  Reads the earlier hook files through ns and ns._hookInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._hookInternals
-- CludesUICdmHooks.lua or an earlier hook file failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local barDataByKey = mod.barDataByKey
local cdmBarFrames = mod.cdmBarFrames
local GetCDMFont = mod.GetCDMFont
local _ecmeFC = mod._ecmeFC

-------------------------------------------------------------------------------
--  Preset/Custom Frames
-------------------------------------------------------------------------------
local _presetFrames = {}
mod._presetFrames = _presetFrames

-- Aura-tracked custom buffs: the WHOLE subsystem lives in one table (_AC)
-- because this file rides the Lua 5.1 200-local cap. bars: barKey ->
-- { holder, container, sids, sig, queued, bdRef, hookedBar }.
--
-- FINAL SHAPE (field-settled 2026-08-08): customs render in ONE engine flow
-- container per bar -- PURE ENGINE, zero Lua per aura event. Under 12.1
-- secrecy (M+/raid combat -- the normal state for our users) Lua can NEVER
-- know whether these auras are active (RequiresNonSecretAura: "protected
-- APIs will return no values"), so customs can never join the bar's own
-- icon row: in-bar mixing needs a Lua-known count. Both workarounds were
-- field-rejected (reserved grey slots push real buffs off center;
-- tail-injection reads off center on centered bars). The engine, however,
-- sizes and CENTERS its own content under full secrecy, so the container
-- hangs off the bar GROWTH-AWARE: directional bars get a tail flowing off
-- the growth edge (reads as the bar simply extending), CENTER bars get a
-- centered strip below/above (the only centered shape physics allows).
-- Actives compact engine-side; when none are up it renders nothing.
--
-- The container lives on a UIParent-anchored holder: engine aura buttons
-- are FORBIDDEN objects, and any anchor path from the bar to them
-- restriction-locks the bar's own geometry (field-proven: the bar stopped
-- re-centering). The holder follows the bar via SetPoint/OnSizeChanged/
-- OnShow/OnHide post-hooks on our own bar frame, coalesced one frame.
local _AC = { bars = {}, syncPending = {} }

-- Position a bar's holder from its CURRENT rect + growth settings. The
-- container point (set at build) mirrors these anchors so the engine flows
-- away from the bar / centers under it.
function _AC.Anchor(barId, rec)
    local barFrame = cdmBarFrames[barId]
    local holderFrame = rec and rec.holder
    if not (barFrame and holderFrame) then return end
    holderFrame:SetShown(barFrame:IsShown())
    -- Visibility rules and bar opacity hide the bar through ALPHA on the bar
    -- frame and its own icons; this holder is UIParent-parented and inherits
    -- none of it, so mirror the bar's effective alpha here: 0 while the bar
    -- is visibility-hidden, else its opacity / out-of-combat fade.
    local bdA = (mod.barDataByKey and mod.barDataByKey[barId]) or rec.bdRef
    holderFrame:SetAlpha(
        barFrame._visHidden and 0 or ((mod.EffectiveBarAlpha and mod.EffectiveBarAlpha(bdA)) or 1)
    )
    holderFrame:ClearAllPoints()
    local success, bl, bb, bw, bh = pcall(barFrame.GetRect, barFrame)
    if not (success and bl) then
        holderFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", -10000, -10000)
        return
    end
    local edge = rec.bdRef
    local gap = (edge and edge.spacing) or 2
    local grow = (edge and edge.growDirection) or "CENTER"
    local cx, cy = bl + bw / 2, bb + bh / 2
    -- END-OF-BAR TAIL for every growth mode (user-directed): customs flow
    -- off the bar's end -- left-grow bars extend left, everything else
    -- extends right; vertical bars extend past their up/down end.
    --
    -- EMPTY BAR (live content width 0, published by LayoutCDMBar -- the
    -- bar's own rect is deliberately stale then): the tail BECOMES the bar.
    -- CENTER-grow bars center the strip ON the bar's position (container
    -- point flips to CENTER so the engine centers it); directional bars
    -- seat it at the FIXED growth edge -- exactly where the first real
    -- buff would render.
    local empty = (barFrame._acLiveW ~= nil and barFrame._acLiveW <= 0.5)
    local wantPt = (empty and grow == "CENTER") and "CENTER" or rec.pt
    if rec.container and wantPt and rec.curPt ~= wantPt then
        rec.curPt = wantPt
        rec.container:ClearAllPoints()
        rec.container:SetPoint(wantPt)
    end
    if edge and edge.verticalOrientation then
        if grow == "UP" then
            holderFrame:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", cx, empty and bb or (bb + bh + gap))
        elseif empty and grow == "CENTER" then
            holderFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
        else
            holderFrame:SetPoint("TOP", UIParent, "BOTTOMLEFT", cx, empty and (bb + bh) or (bb - gap))
        end
    elseif grow == "LEFT" then
        holderFrame:SetPoint("RIGHT", UIParent, "BOTTOMLEFT", empty and (bl + bw) or (bl - gap), cy)
    elseif empty and grow == "CENTER" then
        holderFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
    else
        holderFrame:SetPoint("LEFT", UIParent, "BOTTOMLEFT", empty and bl or (bl + bw + gap), cy)
    end
end

-- LayoutCDMBar pokes the tail on EVERY pass (empty path included): count
-- transitions can land on identical geometry (no size/point events), and
-- the empty<->occupied mode flip must never be missed.
function mod._AuraCustomPoke(barId)
    if _AC.bars[barId] then _AC.MarkSync(barId) end
end

-- Coalesced holder re-anchoring, driven by the bar-frame hooks.
_AC.frame = CreateFrame("Frame")
_AC.frame:Hide()
_AC.frame:SetScript("OnUpdate", function(self)
    self:Hide()
    for barId in pairs(_AC.syncPending) do
        _AC.syncPending[barId] = nil
        _AC.Anchor(barId, _AC.bars[barId])
    end
end)

function _AC.MarkSync(barId)
    if _AC.syncPending[barId] then return end
    _AC.syncPending[barId] = true
    _AC.frame:Show()
end

-- LIVE SET for the preset drain: only the frames ProcessPresetCooldowns and the hot
-- listener loops actually work on (SHOWN racial/custom-spell/item preset frames;
-- custom-BUFF frames are excluded, never register here). _presetFrames above is the
-- permanent identity/reuse map and MUST NEVER BE PRUNED: a pruned key would make the
-- create-only sites build a NEW frame object on the next inject and leak the old one
-- (WoW frames are unreclaimable) -- it grows with every distinct config touched in a
-- session, so the drain iterates this LIVE set instead (reuse-map growth costs
-- nothing). OnShow/OnHide track the frame's own shown flag, matching the old
-- IsShown() gate exactly (alpha/parent-only hiding behaves identically).
local _pcActive = {}

-------------------------------------------------------------------------------
--  Out of Range Coloring for spells added by Spell ID (opt-in, per spell).
--
--  Blizzard's viewer frames tint themselves out of range; a spell added by ID
--  has no viewer frame, so its own-frame icon never did. Mirrors
--  CooldownViewerCooldownItemMixin: the check (C_Spell.EnableSpellRangeCheck)
--  is armed on the icon's Show only when the spell has a range, range is read
--  once there, then only SPELL_RANGE_CHECK_UPDATE repaints (the engine
--  re-dispatches it across target changes), and out of range outranks the
--  resource tint. Override edges (SPELL_UPDATE_ICON,
--  COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED, SPELLS_CHANGED) re-point the check
--  at the live form. The preset pass only paints the stored answer. Writes go
--  to our own texture only. Zero cost unless a spell opts in: nothing is
--  armed, the listener shell is taken on the first opted Show, and its events
--  drop when the last opted icon hides.
--
--  Registrations are per SPELL and shared with Blizzard's viewer and the
--  override arming in CUI_CDM_Rotation.lua: a release never disables an id either of
--  them still holds, and CustomSpellRangeHolds is the same rule from their side.
-------------------------------------------------------------------------------
do
    local refs = {} -- armed spell id -> number of frames holding it
    local armCount = 0 -- shown opted frames (armed, or on a form with no range); the listener is live while > 0
    local listener

    function mod.CustomSpellRangeHolds(spellId) return refs[spellId] ~= nil end

    -- Custom-spell icon tint: out of range first (Blizzard's RefreshIconColor
    -- order), else the resource dim (not the power part under Ignore Resource
    -- Cost). The range tint is written RGBA as Blizzard writes it; the dim
    -- keeps its 3-arg writes.
    local function PaintTint(frame, spellRef, onRealCD)
        local texture = frame._tex
        if not texture then return end
        if frame._rangeOut then
            -- Out of range the icon is range-driven: the dim memo goes (left set, it
            -- would hold the drain unsettled after the spell turned usable) and the
            -- tint write is edge-gated. PaintTint is the only colour writer here.
            frame._lastVertexDim = nil
            if not frame._rangeTinted then
                local c = CooldownViewerConstants and CooldownViewerConstants.ITEM_NOT_IN_RANGE_COLOR
                if c then
                    texture:SetVertexColor(c:GetRGBA())
                    frame._rangeTinted = true
                end
            end
            return
        end
        -- Leaving the range tint needs a white write even when the dim memo is clean.
        local wasTinted = frame._rangeTinted
        if wasTinted then frame._rangeTinted = nil end
        if not onRealCD then
            local isUsable, notEnoughMana = C_Spell.IsSpellUsable(spellRef)
            if notEnoughMana and mod.PresetIgnoresResourceTint(frame) then
                -- Short on power reads as usable; other reasons keep their grey.
                isUsable, notEnoughMana = true, false
            end
            if notEnoughMana then
                texture:SetVertexColor(0.5, 0.5, 1.0)
            elseif not isUsable then
                texture:SetVertexColor(0.4, 0.4, 0.4)
            elseif frame._lastVertexDim or wasTinted then
                texture:SetVertexColor(1, 1, 1)
            end
            frame._lastVertexDim = (not isUsable) or nil
        elseif frame._lastVertexDim or wasTinted then
            texture:SetVertexColor(1, 1, 1)
            frame._lastVertexDim = nil
        end
    end
    mod.PaintCustomSpellTint = PaintTint

    -- Out of range is a readable false only: nil (no target) and a secret answer
    -- both read as in range.
    local function ReadOut(ident)
        local region = C_Spell.IsSpellInRange(ident)
        if not (issecretvalue and issecretvalue(region)) and region == false then return true end
        return nil
    end

    -- Apply one out-of-range flip and repaint (every caller is an edge: Show,
    -- range event, override edge, options). A repaint that lands dimmed wakes
    -- the drain: the write happened outside the pass, and a dim is only polled
    -- for its usable edge while the drain is awake.
    local function SetRangeOut(frame, result)
        if frame._rangeOut == result then return end
        frame._rangeOut = result
        local spellRef = frame._cachedPresetSID
        if spellRef then
            PaintTint(frame, spellRef, frame._lastOnRealCD)
            if frame._lastVertexDim then mod._MarkPresetCdDirty() end
        end
    end

    local function OnRangeEvent(_, evt, spellId)
        local named = not (issecretvalue and issecretvalue(spellId)) and type(spellId) == "number"
        if evt == "SPELL_RANGE_CHECK_UPDATE" then
            -- Blizzard's own registrations are nearly every dispatch, so a readable
            -- id no icon here armed returns before any frame is touched. An
            -- unreadable id (instanced secrecy) re-reads every armed frame. Only
            -- the in/out answer is re-read: arming stays with Sync.
            if named and not refs[spellId] then return end
            for frame in pairs(_pcActive) do
                local armed = frame._rangeArmedSID
                if armed and (not named or armed == spellId) then SetRangeOut(frame, ReadOut(armed)) end
            end
            return
        end
        -- Override edges re-point the opted icons at their live form. The icon
        -- and override events name the base spell (nil = every spell);
        -- SPELLS_CHANGED names none.
        for frame in pairs(_pcActive) do
            if frame._rangeOpted and (not named or frame._cachedPresetSID == spellId) then
                mod.SyncCustomSpellRange(frame)
            end
        end
    end

    -- Hold or drop one frame's opt-in and its armed id. id is the live form to
    -- arm, nil while that form has no range: an opted frame stays on the
    -- override edges either way, so a form that gains a range arms. The range
    -- event itself is held only while some id is armed.
    local function SetArm(frame, ident, opted)
        opted = opted or nil
        if frame._rangeOpted ~= opted then
            frame._rangeOpted = opted
            armCount = armCount + (opted and 1 or -1)
            if opted and armCount == 1 then
                if not listener then
                    listener = mod.TakeShell()
                    listener:SetScript("OnEvent", OnRangeEvent)
                end
                listener:RegisterEvent("SPELL_UPDATE_ICON")
                listener:RegisterEvent("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED")
                listener:RegisterEvent("SPELLS_CHANGED")
            elseif armCount == 0 and listener then
                listener:UnregisterAllEvents()
            end
        end
        local previous = frame._rangeArmedSID
        if previous == ident then return end
        local hadArm = next(refs) ~= nil
        frame._rangeArmedSID = ident
        if previous then
            local num = (refs[previous] or 1) - 1
            refs[previous] = (num > 0) and num or nil
            if not refs[previous] and not mod.BlizzardArmsRange(previous) then
                local held = false
                if mod._oorArmed then
                    for _, shade in pairs(mod._oorArmed) do
                        if shade == previous then
                            held = true
                            break
                        end
                    end
                end
                if not held then C_Spell.EnableSpellRangeCheck(previous, false) end
            end
        end
        if ident then
            if not refs[ident] then C_Spell.EnableSpellRangeCheck(ident, true) end
            refs[ident] = (refs[ident] or 0) + 1
        end
        local hasArm = next(refs) ~= nil
        if hasArm ~= hadArm then
            if hasArm then
                listener:RegisterEvent("SPELL_RANGE_CHECK_UPDATE")
            else
                listener:UnregisterEvent("SPELL_RANGE_CHECK_UPDATE")
            end
        end
    end

    -- Resolve one custom-spell frame: hold or drop its opt-in, arm, re-point
    -- (live override) or release its range check, then read range once.
    -- Called on edges only: Show, override edges and the options toggle.
    function mod.SyncCustomSpellRange(frame)
        local spellRef = frame._cachedPresetSID
        if not spellRef then
            local m = frame._pfKey and frame._pfKey:match(":(%d+)$")
            spellRef = m and tonumber(m)
            frame._cachedPresetSID = spellRef
        end
        local wanted, opted
        local cas = spellRef and mod._cdmAnyCustomRangeColor and mod.GetEffectiveCustomActiveState(spellRef)
        if cas and cas.outOfRangeColoring then
            opted = true
            local ovr = C_SpellBook.FindSpellOverrideByID(spellRef)
            local live = (ovr and ovr > 0) and ovr or spellRef
            if C_Spell.SpellHasRange(live) then wanted = live end
        end
        SetArm(frame, wanted, opted)
        SetRangeOut(frame, wanted and ReadOut(wanted) or nil)
    end

    function mod.ReleaseCustomSpellRange(frame) SetArm(frame, nil, nil) end

    -- Options toggle (and the gate latching on): re-resolve every shown
    -- custom-spell icon right away.
    function mod.RefreshCustomSpellRange()
        for frame in pairs(_pcActive) do
            if frame._isCustomSpellFrame and not frame._isCustomBuffFrame then
                mod.SyncCustomSpellRange(frame)
            end
        end
    end
end

local function _RegisterPresetLive(frame, fkey)
    frame._pfKey = fkey
    frame:HookScript("OnShow", function(self)
        _pcActive[self] = true
        -- Show is a state edge (events may have fired while hidden):
        -- re-read and re-push everything on the next pass.
        self._cdPushArm = true
        if self._isItemPresetFrame then
            self._itemWalkArm = true
            self._countArm = true
        end
        -- Out of Range Coloring arms (or re-arms) on this edge.
        if mod._cdmAnyCustomRangeColor and self._isCustomSpellFrame and not self._isCustomBuffFrame then
            mod.SyncCustomSpellRange(self)
        end
        if mod._MarkPresetCdDirty then mod._MarkPresetCdDirty() end
    end)
    frame:HookScript("OnHide", function(self)
        _pcActive[self] = nil
        -- A hidden icon holds no range registration; its Show re-arms it.
        if self._rangeOpted then mod.ReleaseCustomSpellRange(self) end
    end)
    if frame:IsShown() then _pcActive[frame] = true end
end

-------------------------------------------------------------------------------
--  Always Show Buffs placeholders
--  Our-owned icon frames that hold an INACTIVE tracked buff's slot so the buff
--  "always shows" (greyed) without editing Blizzard's Edit Mode layout. Mirrors
--  _presetFrames (a UIParent Frame + .Icon + .Cooldown) so the existing
--  DecorateFrame / LayoutCDMBar pipeline styles and positions them like any
--  real icon. Keyed barKey:ph:spellID. Never armed with a cooldown (no strobe).
-------------------------------------------------------------------------------
local _placeholderFrames = {}
mod._placeholderFrames = _placeholderFrames

-- Hide every placeholder. Called once at the start of each collect pass; the
-- pass then re-shows only the placeholders it injects, so a placeholder whose
-- buff went active, or whose bar was toggled off/disabled, ends up hidden.
local function HideAllPlaceholders()
    for _, frame in pairs(_placeholderFrames) do
        if frame:IsShown() then frame:Hide() end
    end
end
mod.HideAllPlaceholders = HideAllPlaceholders

-- Injected custom/preset buff own-frames (buff-family bars). Tracked so the
-- collect pass can hide them all up front and re-show only the active ones,
-- exactly like placeholders -- the buff-phase cleanup loops only disable swipe
-- (correct for Blizzard pool frames, which must never be Hidden), so OUR frames
-- need their own hide pass or an inactive/expired/orphaned one would linger.
local _injectedCustomBuffFrames = setmetatable({}, { __mode = "k" })
local function HideAllInjectedCustomBuffs()
    for frame in pairs(_injectedCustomBuffFrames) do
        if frame:IsShown() then frame:Hide() end
    end
end
mod.HideAllInjectedCustomBuffs = HideAllInjectedCustomBuffs

-- Spellbook name -> first known castable id with that name. A tracked-buff slot
-- holds AURA ids, and an aura carries no link back to the spell that applies it
-- (every identity API is a fixed point on it), while the CASTABLE side is where
-- the talent override lives; an aura and its caster share a name, so the book is
-- the only available bridge. Built on first use, dropped on talent change (the
-- override it feeds is talent-dependent). An EMPTY result is treated as "not
-- built yet" rather than cached: the first placeholder can resolve before the
-- spellbook populates at login, and caching that would strand the bridge until
-- the next talent change (a real character always has spells, so empty only
-- means too early). A pcall failure IS cached, since a missing API won't start working.
local _bookByName
local function EnsureBookNameMap()
    if not _bookByName then
        local built = {}
        local success = pcall(function()
            local nLines = C_SpellBook.GetNumSpellBookSkillLines()
            for index = 1, (nLines or 0) do
                local li = C_SpellBook.GetSpellBookSkillLineInfo(index)
                if li and li.itemIndexOffset and li.numSpellBookItems then
                    for jdx = li.itemIndexOffset + 1, li.itemIndexOffset + li.numSpellBookItems do
                        local it = C_SpellBook.GetSpellBookItemInfo(jdx, Enum.SpellBookSpellBank.Player)
                        local bsid = it and it.spellID
                        if bsid then
                            local nm = C_Spell.GetSpellName(bsid)
                            if nm and built[nm] == nil then built[nm] = bsid end
                        end
                    end
                end
            end
        end)
        if not success then
            _bookByName = {}
        elseif next(built) then
            _bookByName = built
        else
            return built -- too early; retry on the next call
        end
    end
    return _bookByName
end
local function BookIDForName(name)
    if type(name) ~= "string" or name == "" then return nil end
    return EnsureBookNameMap()[name]
end
mod.WipeCdmBookNameCache = function() _bookByName = nil end
mod.CdmBookIDForName = BookIDForName

-- Resolve the spell whose ICON an inactive placeholder should paint. An ACTIVE
-- buff frame renders the live aura, so a talent that REPLACES a spell shows the
-- replacement (e.g. Hellcaller: Wither); an INACTIVE frame has no aura to read
-- and falls back to cooldownInfo, which still names the pre-talent spell, so the
-- same icon changes art as the aura comes and goes. Two ways a replacement can
-- show up, tried in order: (1) something in the slot's identity set (resolved
-- id, cooldownInfo's base, override or linked ids) is itself overridden --
-- covers CASTABLE-keyed slots; (2) nothing is overridden, the normal state for a
-- tracked-buff slot, since it holds AURA ids and an aura carries no override
-- even when a talent replaces the spell behind it (e.g. Destruction's Immolate
-- slot resolves to aura 157736, reports overrideSpellID == spellID, and merely
-- LISTS Wither's aura 445474 as a link) -- fall back to the spellbook, matching
-- by name. Returns sid untouched when neither applies (every spec without a
-- replacing talent). Callers use the result for ART ONLY: identity, pooling and settings resolution stay keyed on the original id.
local function ResolvePlaceholderIconSID(spellRef, cdID)
    local FO = C_SpellBook and C_SpellBook.FindSpellOverrideByID
    if not FO or type(spellRef) ~= "number" or spellRef <= 0 then return spellRef end
    if issecretvalue and issecretvalue(spellRef) then return spellRef end

    local function TryID(ident)
        if type(ident) ~= "number" or ident <= 0 then return nil end
        if issecretvalue and issecretvalue(ident) then return nil end
        local o = FO(ident)
        if type(o) == "number" and o > 0 and o ~= ident then return o end
        return nil
    end

    local hit = TryID(spellRef)
    if hit then return hit end

    local getCdInfo = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    local details = (cdID ~= nil and getCdInfo) and getCdInfo(cdID) or nil
    if details then
        hit = TryID(details.spellID) or TryID(details.overrideSpellID)
        if hit then return hit end
        if details.linkedSpellIDs then
            for _, lid in ipairs(details.linkedSpellIDs) do
                hit = TryID(lid)
                if hit then return hit end
            end
        end
    end

    -- Nothing in the slot is overridden, the normal state for a tracked-buff slot
    -- (it holds aura ids, and auras carry no override even when a talent replaces
    -- the spell behind them, e.g. Hellcaller's Immolate slot reports
    -- overrideSpellID == spellID and merely LISTS Wither's aura as a link).
    -- Bridge to the castable by name and take ITS live override, where the
    -- replacement actually shows up. One spellbook scan per talent change; no-op without a replacing talent.
    local NameOf = C_Spell and C_Spell.GetSpellName
    local nm = NameOf and NameOf(spellRef)
    local castable = BookIDForName(nm)
    if castable then
        local o = FO(castable)
        if type(o) == "number" and o > 0 and o ~= castable then return o end
    end

    -- The spellbook lists the REPLACEMENT rather than the base, so a replaced
    -- spell's name can be absent from it entirely and the lookup above finds
    -- nothing to follow; the test then inverts: when a LINKED variant's name is
    -- in the book and this slot's own name is not, the linked form is what the
    -- player actually casts (requiring the slot's name to be absent keeps this
    -- from firing while both forms are available). Return the BOOK id, not the
    -- linked id: a linked id is the variant's AURA (Wither's DoT 445474) while
    -- the book id is the CASTABLE the player actually has (Wither 445468), and
    -- the two carry different art (returning an aura here painted a flicker
    -- across a hero-talent swap, since the castable branch above returns a castable too).
    if details and details.linkedSpellIDs and not castable then
        for _, lid in ipairs(details.linkedSpellIDs) do
            if type(lid) == "number" and lid > 0 and not (issecretvalue and issecretvalue(lid)) then
                local book = BookIDForName(NameOf and NameOf(lid))
                if book then return book end
            end
        end
    end
    return spellRef
end
mod.ResolvePlaceholderIconSID = ResolvePlaceholderIconSID

-- identKey: optional pooling identity, defaulting to spellID. Buff
-- placeholders pass one so two viewer slots that collide on spellID do not
-- share a single pooled frame (see the collision note at the call site).
local function GetOrCreatePlaceholderFrame(barId, spellId, iconID, identKey)
    local fkey = barId .. ":ph:" .. tostring(identKey or spellId)
    local frame = _placeholderFrames[fkey]
    if not frame then
        frame = CreateFrame("Frame", nil, UIParent)
        frame:SetSize(36, 36)
        frame:Hide()
        frame:EnableMouse(true)
        if frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(false) end
        local texture = frame:CreateTexture(nil, "ARTWORK")
        texture:SetAllPoints()
        mod.CdmOwnIconCrop(texture)
        frame.Icon = texture
        frame._tex = texture
        local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
        cd:SetAllPoints()
        cd:SetDrawEdge(false)
        cd:SetDrawBling(false)
        cd:SetHideCountdownNumbers(true)
        cd:EnableMouse(false)
        if cd.SetMouseClickEnabled then cd:SetMouseClickEnabled(false) end
        if cd.SetMouseMotionEnabled then cd:SetMouseMotionEnabled(false) end
        cd:Clear() -- permanent placeholder: never arm a 0-duration swipe (strobe)
        frame.Cooldown = cd
        frame._cooldown = cd
        frame._isPlaceholderFrame = true
        frame._phSpellID = spellId
        -- Never claimed/routed like a Blizzard frame; carries no live aura state.
        frame.cooldownID = nil
        frame.cooldownInfo = nil
        frame.auraInstanceID = nil
        frame.wasSetFromAura = nil
        frame:SetScript("OnEnter", function(self)
            local ffc = _ecmeFC[self]
            local bd2 = ffc and ffc.barKey and barDataByKey[ffc.barKey]
            if not bd2 or not bd2.showTooltip then return end
            if not self._phSpellID then return end
            -- A placeholder that renders at alpha 0 has nothing under the
            -- cursor to describe: "Keep Buffs in Same Place"
            -- (bd2.hidePlaceholderIcon) and hosted "Visibility When Missing:
            -- Hidden" (_missingHidden) both reserve the slot invisibly, so the
            -- buff is NOT active and its tooltip must stay down. Same pair of
            -- flags the three opacity passes test before forcing alpha 0.
            if bd2.hidePlaceholderIcon or self._missingHidden then return end
            -- Honor the global "Show Tooltips" visibility mode (Blizzard Skin).
            if
                CUI
                and CUI._tooltipSuppressedByMode
                and CUI._tooltipSuppressedByMode(GameTooltip)
            then
                return
            end
            GameTooltip_SetDefaultAnchor(GameTooltip, self)
            GameTooltip:SetSpellByID(self._phSpellID)
            if CUI and CUI._repointTooltipAtCursor then
                CUI._repointTooltipAtCursor(GameTooltip)
            end
            GameTooltip:Show()
        end)
        frame:SetScript("OnLeave", GameTooltip_Hide)
        _placeholderFrames[fkey] = frame
    end
    -- Re-assert on reuse: a pooled frame outlives a talent swap, so the id it
    -- was created with can name the pre-talent spell (its tooltip would still
    -- read Immolate on a Hellcaller Wither slot).
    frame._phSpellID = spellId
    if iconID then frame._tex:SetTexture(iconID) end
    return frame
end

-- Own-frame for a custom/preset buff (cast-timer driven) on a buff-family bar.
-- Created once per (barKey, spellID); reused across reanchors. Mirrors the frame
-- the legacy custom_buff renderer builds, but the buff-phase injection drives its
-- cooldown swipe and lets CollectAndReanchor slot it next to Blizzard buff frames.
-- OnCooldownDone queues a reanchor so the expired buff drops out of the layout.
local function GetOrCreateCustomBuffFrame(barId, spellRef)
    local fkey = barId .. ":custombuff:" .. spellRef
    local frame = _presetFrames[fkey]
    if not frame then
        frame = CreateFrame("Frame", nil, UIParent)
        frame:SetSize(36, 36)
        frame:Hide()
        frame:EnableMouse(false)
        local texture = frame:CreateTexture(nil, "ARTWORK")
        texture:SetAllPoints()
        mod.CdmOwnIconCrop(texture)
        frame.Icon = texture
        frame._tex = texture
        local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
        cd:SetAllPoints()
        cd:SetDrawEdge(false)
        cd:SetDrawBling(false)
        cd:SetReverse(true)
        frame.Cooldown = cd
        frame._cooldown = cd
        frame._isCustomSpellFrame = true
        frame._isCustomBuffFrame = true
        frame.cooldownID = nil
        frame.cooldownInfo = nil
        cd:HookScript("OnCooldownDone", function()
            -- Re-lay-out the bar so the expired buff is removed. Also poke the
            -- legacy custom_buff updater (harmless for buff bars).
            if mod.QueueCustomBuffUpdate then C_Timer.After(0, mod.QueueCustomBuffUpdate) end
            if mod.QueueReanchor then C_Timer.After(0, mod.QueueReanchor) end
        end)
        local iconSID = mod.LustPresetIconSpellID and mod.LustPresetIconSpellID(spellRef) or spellRef
        local spInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(iconSID)
        if spInfo and spInfo.iconID and frame._tex then frame._tex:SetTexture(spInfo.iconID) end
        _presetFrames[fkey] = frame
        _injectedCustomBuffFrames[frame] = true
    end
    return frame
end
mod.GetOrCreateCustomBuffFrame = GetOrCreateCustomBuffFrame

-- Own-frame for an item (icon + item cooldown + bag count), shared by the
-- CD/utility injection (Phase 3) and the buff-family injection. Created once per
-- (barKey, itemID). Uses the preset icon when known, else the live item icon for
-- arbitrary user-added IDs. Returns nil if the icon isn't loaded yet.
local function GetOrCreateItemPresetFrame(barId, itemId)
    local fkey = barId .. ":item:" .. itemId
    local frame = _presetFrames[fkey]
    if frame then return frame end

    local itemPresets = mod.CDM_ITEM_PRESETS
    local preset
    if itemPresets then
        for _, pr in ipairs(itemPresets) do
            if pr.itemID == itemId then
                preset = pr
                break
            end
            if pr.altItemIDs then
                for _, alt in ipairs(pr.altItemIDs) do
                    if alt == itemId then
                        preset = pr
                        break
                    end
                end
            end
        end
    end
    local iconTex = preset and preset.icon or C_Item.GetItemIconByID(itemId)
    if not iconTex then return nil end

    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(36, 36)
    frame:Hide()
    -- Enable mouse motion (OnEnter/OnLeave) for tooltips but pass through clicks.
    frame:EnableMouse(true)
    if frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(false) end
    local texture = frame:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints()
    texture:SetTexture(iconTex)
    mod.CdmOwnIconCrop(texture)
    frame.Icon = texture
    frame._tex = texture
    local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    cd:SetHideCountdownNumbers(true)
    cd:EnableMouse(false)
    if cd.SetMouseClickEnabled then cd:SetMouseClickEnabled(false) end
    if cd.SetMouseMotionEnabled then cd:SetMouseMotionEnabled(false) end
    -- Item cooldowns fire no event when they naturally expire, so the
    -- desaturation pass (ProcessPresetCooldowns) wouldn't re-run at the ready
    -- edge and the icon would stay greyed until some unrelated event marked it
    -- dirty (the CD-ready glow polls continuously and lights up instantly, so
    -- without this the pot glows while still desaturated). Poke the processor at
    -- the expiry edge so the next tick re-evaluates count/CD/lockout (a plain
    -- re-saturate would be wrong when the last charge was just used -- total==0 must keep it greyed).
    cd:SetScript("OnCooldownDone", function()
        if mod._MarkPresetCdDirty then mod._MarkPresetCdDirty() end
    end)
    frame.Cooldown = cd
    frame._cooldown = cd
    frame._isItemPresetFrame = true
    frame._presetItemID = itemId
    frame._presetData = preset
    frame.cooldownID = nil
    frame.cooldownInfo = nil
    frame.layoutIndex = 99999
    local countFS = frame:CreateFontString(nil, "OVERLAY")
    CUI.ApplyIconTextFont(countFS, GetCDMFont(), 11, "cdm")
    countFS:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 2)
    frame._itemCountText = countFS
    frame:SetScript("OnEnter", function(self)
        if not self._presetItemID then return end
        local ffc = _ecmeFC[self]
        local bd2 = ffc and ffc.barKey and barDataByKey[ffc.barKey]
        if not bd2 or not bd2.showTooltip then return end
        -- Honor the global "Show Tooltips" visibility mode (Blizzard Skin).
        if
            CUI
            and CUI._tooltipSuppressedByMode
            and CUI._tooltipSuppressedByMode(GameTooltip)
        then
            return
        end
        GameTooltip_SetDefaultAnchor(GameTooltip, self)
        -- Pot presets tooltip the resolved display variant (may be another
        -- rank / Fleeting / the swapped-in partner pot), not the primary.
        -- Other presets tooltip the first owned family member (the id the
        -- count walk points _itemCdSource at), so a warlock holding only a
        -- Demonic Healthstone sees that stone; nothing owned -> the primary.
        local tipID = self._displayItemID
        if not tipID then
            local _, owned = mod._ReadItemPresetCount(self)
            tipID = owned
        end
        GameTooltip:SetItemByID(tipID or self._presetItemID)
        -- Re-assert the cursor anchor after content is set (item setters can drop
        -- it under "Anchor to Cursor", leaving the tip invisible). No-op otherwise.
        if CUI and CUI._repointTooltipAtCursor then
            CUI._repointTooltipAtCursor(GameTooltip)
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", GameTooltip_Hide)
    _presetFrames[fkey] = frame
    _RegisterPresetLive(frame, fkey)
    return frame
end
mod.GetOrCreateItemPresetFrame = GetOrCreateItemPresetFrame

-------------------------------------------------------------------------------
--  Empty Slot: a purely decorative placeholder that reserves one grid position
--  with nothing drawn (no texture, no cooldown, no border) -- true blank space,
--  so a bar can visually group its icons. One frame per marker (unique per Add,
--  see ns.NewEmptySlotMarker), reused across reanchors like every other custom
--  frame. Never registered with _RegisterPresetLive: it has no cooldown to poll
--  (zero cost beyond the one-time frame creation).
-------------------------------------------------------------------------------
local function GetOrCreateEmptySlotFrame(marker)
    local fkey = "emptyslot:" .. marker
    local frame = _presetFrames[fkey]
    if frame then return frame end

    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(36, 36)
    frame:Hide()
    frame:EnableMouse(false)
    frame._isEmptySlotFrame = true
    frame.cooldownID = nil
    frame.cooldownInfo = nil
    frame.layoutIndex = 99999
    _presetFrames[fkey] = frame
    return frame
end
mod.GetOrCreateEmptySlotFrame = GetOrCreateEmptySlotFrame

-- Crafted-quality pip for item frames -- the action bars' Show Rank Icon, for
-- CDM. Those read C_ActionBar.GetProfessionQualityInfo, which needs an action
-- slot; an item frame has only an item id, so this asks the item-side call that
-- returns the same CraftingQualityInfo struct, and takes iconInventory off it
-- exactly as the action bars do. Blizzard's own callers pass a LINK rather than
-- a bare id (and the action bar work recorded bare-id reads coming back nil), so
-- prefer the link and keep the id as the fallback.
-- Per bar and off by default: nothing here is created or called until a bar
-- turns it on. The resolved atlas is memoised per item so the steady state is
-- one compare; it re-reads when the icon changes which item it is showing,
-- which for a pot preset is the point (the pip follows the rank resolved).
-- The memo is deliberately TRI-STATE. An item whose data the client has not
-- cached yet answers nil, and that is the state on the pass right after login,
-- so caching it as "no quality" would leave the pip permanently missing on
-- exactly the items it is for: nil = unresolved, retry next pass (item data is
-- requested here, so the retry has something to find); false = resolved, this
-- item has no crafted quality, stop asking.
local _cdmQualityAtlas = {}
local function CdmQualityAtlasFor(q)
    local hit = _cdmQualityAtlas[q]
    if hit ~= nil then return hit or nil end
    local probe = C_Texture and C_Texture.GetAtlasInfo
    local nameList = {
        "Professions-Icon-Quality-Tier" .. q .. "-Inv-Small",
        "Professions-Icon-Quality-Tier" .. q .. "-Small",
        "Professions-Icon-Quality-Tier" .. q,
    }
    for index = 1, #nameList do
        if probe and probe(nameList[index]) then
            _cdmQualityAtlas[q] = nameList[index]
            return nameList[index]
        end
    end
    _cdmQualityAtlas[q] = false
    return nil
end

local function ApplyItemQualityPip(frame, itemId, enabled)
    if not enabled then
        if frame._qualityHolder then frame._qualityHolder:Hide() end
        frame._qualityItemID, frame._qualityAtlas = nil, nil
        return
    end
    if not itemId then return end
    -- Resolved already for this exact item (false = resolved as "no quality").
    if frame._qualityItemID == itemId and frame._qualityAtlas ~= nil then return end

    local atlas
    local ts = C_TradeSkillUI
    local itemLink = C_Item and C_Item.GetItemInfo and select(2, C_Item.GetItemInfo(itemId))
    if not itemLink and C_Item and C_Item.RequestLoadItemDataByID then
        -- Not cached yet. Ask for it and leave the memo unresolved so the next
        -- pass retries rather than baking in the miss.
        C_Item.RequestLoadItemDataByID(itemId)
    end
    -- Blizzard's own item buttons (SetItemCraftingQualityOverlay in
    -- ItemButtonTemplate) ask REAGENT quality first and only then CRAFTED, and
    -- that order is the whole fix: a live probe on this bar had the crafted
    -- calls answering nil for every potion on it -- ranked consumables carry a
    -- reagent quality, not a crafted one. Both return the same
    -- CraftingQualityInfo, so iconInventory comes off whichever answers.
    if ts and ts.GetItemReagentQualityInfo then
        local success, details = pcall(ts.GetItemReagentQualityInfo, itemLink or itemId)
        atlas = success and details and details.iconInventory or nil
    end
    if not atlas and ts and ts.GetItemCraftedQualityInfo then
        local success, details = pcall(ts.GetItemCraftedQualityInfo, itemLink or itemId)
        atlas = success and details and details.iconInventory or nil
    end
    if not atlas and ts and ts.GetItemCraftedQualityByItemInfo then
        -- Same fallback shape the action bars keep: a bare quality number,
        -- mapped through the probe.
        local success, q = pcall(ts.GetItemCraftedQualityByItemInfo, itemLink or itemId)
        if success and type(q) == "number" and q >= 1 and q <= 5 then atlas = CdmQualityAtlasFor(q) end
    end
    if not atlas then
        if frame._qualityHolder then frame._qualityHolder:Hide() end
        -- Only settle on "no quality" once the item is actually known.
        if itemLink then
            frame._qualityItemID, frame._qualityAtlas = itemId, false
        end
        return
    end
    frame._qualityItemID, frame._qualityAtlas = itemId, atlas

    local holderFrame = frame._qualityHolder
    if not holderFrame then
        -- Own holder frame rather than a texture on f: the item frame's
        -- Cooldown is a CHILD frame, and a child draws above every texture of
        -- its parent whatever the draw layer, so a pip parented to f sits under
        -- the swipe. This is why the item count text is reparented to a text
        -- overlay too, and what the action bars' rank icon does.
        holderFrame = CreateFrame("Frame", nil, frame)
        holderFrame:SetAllPoints(frame)
        holderFrame:SetFrameLevel((frame:GetFrameLevel() or 1) + 18)
        holderFrame:EnableMouse(false)
        frame._qualityHolder = holderFrame
        frame._qualityTex = holderFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    end
    local texture = frame._qualityTex
    -- Unknown atlas reads as no pip, never as an error.
    if not pcall(texture.SetAtlas, texture, atlas, true) then
        frame._qualityAtlas = false
        holderFrame:Hide()
        return
    end
    -- Same proportion the action bars use (Blizzard centers the overlay 14,-14
    -- from the TOPLEFT of a 45px button), scaled to whatever size the bar runs.
    local sc = (frame:GetWidth() or 36) / 36
    texture:ClearAllPoints()
    texture:SetPoint("CENTER", holderFrame, "TOPLEFT", 11 * sc, -11 * sc)
    texture:SetScale(sc)
    texture:Show()
    holderFrame:Show()
end

Inner._AC, Inner._injectedCustomBuffFrames, Inner._pcActive = _AC, _injectedCustomBuffFrames, _pcActive
Inner._presetFrames, Inner._RegisterPresetLive = _presetFrames, _RegisterPresetLive
Inner.ApplyItemQualityPip = ApplyItemQualityPip
Inner.GetOrCreateCustomBuffFrame = GetOrCreateCustomBuffFrame
Inner.GetOrCreateEmptySlotFrame = GetOrCreateEmptySlotFrame
Inner.GetOrCreateItemPresetFrame = GetOrCreateItemPresetFrame
Inner.GetOrCreatePlaceholderFrame = GetOrCreatePlaceholderFrame
Inner.HideAllInjectedCustomBuffs = HideAllInjectedCustomBuffs
Inner.HideAllPlaceholders = HideAllPlaceholders
Inner.ResolvePlaceholderIconSID = ResolvePlaceholderIconSID
Inner.broken = false
