if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUICdmTalentConditions.lua
--  Per-spell Talent Conditions for cooldown/utility icons: the icon shows only
--  while every condition on it holds ("talent X taken", "talent Y not taken").
--  A condition that fails drops the icon from the reanchor pass exactly like an
--  unlearned spell (ns.TalentCondFilterPass, called by CollectAndReanchor before
--  Phase 3): Phase 4 parks it and the icons after it close the gap.
--  Empty Slots store conditions under their unique marker in the same CD-family
--  store and check them during injection, after the Blizzard-frame filter.
--
--  Stored on the spell's own per-spell entry (spellSettingsCD[sid]):
--      talentConditions = { { nodeID = n, entryID = e, spellID = s, taken = bool }, ... }
--  entryID only for a choice node (which side must be picked); spellID is for
--  display only. Per spell ONLY, like Custom Icon: never written to the
--  Apply-to-Bar tiers, so every read is a rawget on the spell's own entry.
--
--  Cost: nothing until some saved spell has a condition. ns._cdmAnyTalentCond is
--  set once by RescanTalentCondFlag at setup, or by the options popup on first
--  use (monotonic, like the other per-spell gates). Once set, the reanchor asks
--  the filter per claimed cooldown frame. The check itself is the parent's
--  (CludesUI.TalentConditionsHold in CludesUI_SharedHelpers.lua, shared
--  with the WoW Forever swing timer): a node-state cache filled lazily from
--  C_Traits, one lookup per node, keyed by the active config ID (changes on a
--  spec swap only) and wiped by ns.TalentCondInvalidate on every talent event
--  (edits and loadout loads keep the config ID). Talent edits already queue a
--  full CDM rebuild, which re-runs the filter, so no events of our own are
--  registered.
-------------------------------------------------------------------------------
local _, mod = ...

local wipe = wipe
local tremove = table.remove

local Hold = CludesUI.TalentConditionsHold

-- Talent edit landed (TRAIT_CONFIG_UPDATED and friends): forget every node.
mod.TalentCondInvalidate = CludesUI.TalentCondInvalidate

-- True when the node (or, for a choice node, that side of it) is taken right now.
mod.TalentCondIsTaken = CludesUI.TalentCondIsTaken

-- True when every condition in the list holds (an empty or missing list holds).
function mod.TalentConditionsHold(conds)
    return Hold(conds)
end

-- Empty Slots are injected after TalentCondFilterPass, with no spell resolver.
function mod.EmptySlotTalentConditionsHold(barId, marker)
    if not mod._cdmAnyTalentCond then
        return true
    end
    local storage = mod.GetSpellSettingsStore(barId)
    local record = storage and storage[marker]
    local conds = type(record) == "table" and rawget(record, "talentConditions")
    return not conds or mod.TalentConditionsHold(conds)
end

-------------------------------------------------------------------------------
--  Reanchor filter. Drops every CD/utility frame whose conditions fail this pass
--  and records it per bar, so the reseeds still count the spell as present: it
--  keeps its preview slot and its conditions stay reachable. The records are
--  reused tables, wiped per pass and read-only for callers.
-------------------------------------------------------------------------------
local _ecmeFC = mod._ecmeFC
local _hookFrameData = mod._hookFrameData
local _hiddenSets = {} -- barKey -> { [spellID] = true }
local _hiddenFrames = {} -- barKey -> { frame, ... }
local _anyHidden = false
local _empty = {}

-- Spells the filter dropped from this bar in the last pass (shared empty table when none).
function mod.TalentCondHiddenSet(barId)
    return (barId and _hiddenSets[barId]) or _empty
end

-- The dropped frames themselves, same lifetime (shared empty list when none).
function mod.TalentCondHiddenFrames(barId)
    return (barId and _hiddenFrames[barId]) or _empty
end

-- cdFrames: CollectAndReanchor's per-bar frame lists (edited in place). Called only
-- while ns._cdmAnyTalentCond is set, which never clears in a session, so every
-- claimed frame passes through here and a stale tcHidden tag always gets cleared.
function mod.TalentCondFilterPass(cdFrames)
    if _anyHidden then
        for _, s in pairs(_hiddenSets) do
            wipe(s)
        end
        for _, l in pairs(_hiddenFrames) do
            wipe(l)
        end
        _anyHidden = false
    end
    local configID -- read once, on the first frame that carries conditions (false = none)
    for bk, frameList in pairs(cdFrames) do
        for index = #frameList, 1, -1 do
            local widget = frameList[index]
            local fc = _ecmeFC[widget]
            if fc then
                local conds
                local cdSid = fc.replacesCd
                if cdSid then
                    -- Replace-with-Buff frame: follows its cooldown's own CD-family
                    -- entry. The resolver would read the buff store for this
                    -- buff-viewer frame on any bar that has ever hosted a buff.
                    local storage = mod.GetSpellSettingsStore(bk)
                    local e = storage and storage[cdSid]
                    conds = type(e) == "table" and rawget(e, "talentConditions") or nil
                elseif not fc.isHostedBuff then
                    -- Hosted buffs are buff-family and never carry the setting.
                    local spellRef = fc.spellID
                    if spellRef and spellRef > 0 then
                        local ss = mod.ResolveSpellSettings(widget, spellRef, false, bk)
                        conds = ss and rawget(ss, "talentConditions")
                    end
                end
                local hide = false
                if conds then
                    if configID == nil then
                        configID = C_ClassTalents.GetActiveConfigID() or false
                    end
                    hide = not Hold(conds, configID)
                end
                if hide then
                    tremove(frameList, index)
                    local spellRef = fc.spellID
                    if spellRef then
                        local set = _hiddenSets[bk]
                        if not set then
                            set = {}
                            _hiddenSets[bk] = set
                            _hiddenFrames[bk] = {}
                        end
                        set[spellRef] = true
                        local entries = _hiddenFrames[bk]
                        entries[#entries + 1] = widget
                        _anyHidden = true
                    end
                    -- A hidden icon stays silent: out of the CD Ready Sound watch and
                    -- disarmed; the tag (our FC entry, never the frame) also mutes the
                    -- available-alert hook until a pass lets the frame back in.
                    fc.tcHidden = true
                    mod._cdReadySoundWatch[widget] = nil
                    local fd = _hookFrameData[widget]
                    if fd then
                        fd._cdReadyArmed = false
                    end
                    if cdSid then
                        -- Buff-viewer frame: Phase 4 leaves these hands-off, so blank it
                        -- here or it stays at its old slot over the collapsed bar. The
                        -- SetPoint hook keeps it blank while unclaimed; a re-claim
                        -- restores alpha and anchor.
                        if fd then
                            fd._cdmAnchor = nil
                        end
                        widget:SetAlpha(0)
                        -- Alpha does not stop hit-testing: drop the tooltip motion the bar
                        -- gave it, or it keeps catching hover and [@mouseover] over that
                        -- slot. Every pass (Blizzard's re-acquire turns it back on); a
                        -- re-claim re-applies the bar's tooltip setting. Mouse calls are
                        -- blocked in combat, where it keeps its motion until the next pass.
                        if widget.EnableMouseMotion and not InCombatLockdown() then
                            widget:EnableMouseMotion(false)
                        end
                    end
                elseif fc.tcHidden then
                    fc.tcHidden = nil
                end
            end
        end
    end
end

-- Talent Conditions gate: set ns._cdmAnyTalentCond once if any saved spell (any spec)
-- has a condition. Skips the reanchor filter for non-users. Same monotonic, scanned-once
-- contract as the other per-spell gates; talentConditions is never written to bar tiers.
function mod.RescanTalentCondFlag()
    if mod._cdmAnyTalentCond or mod._talentCondFlagScanned then
        return
    end
    if not CludesUIDB then
        return
    end
    mod._talentCondFlagScanned = true
    mod.ForEachSavedSettingsBlock(function(ss)
        local conds = rawget(ss, "talentConditions")
        if type(conds) == "table" and #conds > 0 then
            mod._cdmAnyTalentCond = true
            return true
        end
    end)
end
