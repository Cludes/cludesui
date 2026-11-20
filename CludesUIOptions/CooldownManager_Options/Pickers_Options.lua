if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CooldownManager_Options\Pickers_Options.lua
--  Cooldown Manager options: buff pickers, spell/item/slot ID popups, value
--  popups and EnsureAssignedSpells. Definitions only; the shared helpers come
--  from ns._CDMO_OptEnv (filled by CUI_CooldownManager_Options.lua).
-------------------------------------------------------------------------------
local mod = CludesUI._ModuleNS["CludesUICooldownManager"]
if not mod then
    return
end -- module disabled: no options page

-- The options page pool (CludesUI_FramePool.lua): a frame made under a pool
-- host (a kept picker menu) is handed out again reset to fresh; anywhere else
-- this is the plain CreateFrame. Each picker menu is one kept frame for the
-- session (PoolKept), dressed again on each open. A picker remembers its
-- anchor with the anchor's dress generation (PoolGen): an anchor a rebuild
-- dressed again for a new build is another anchor, as a new frame was.
local CreateFrame = CludesUI._Pool.CreateFrame
local PoolKept, PoolGen = CludesUI._Pool.Kept, CludesUI._Pool.Gen

-- Ensure assignedSpells is populated from live icons if nil; shared by spell picker, preview, and all add/remove handlers.
local function EnsureAssignedSpells(barKeyE)
    local environ = mod._CDMO_OptEnv
    local NormalizeToBase, ResolveToLive = environ.NormalizeToBase, environ.ResolveToLive
    local sd = mod.GetBarSpellData(barKeyE)
    if not sd then
        return sd
    end
    if sd.assignedSpells then
        -- Normalize overrides to base IDs and dedupe in one pass. EXCEPTION: user-typed
        -- custom spell IDs (sd.customSpellIDs) are EXACT identities (tag, Phase 3 injection,
        -- and duration keys are all keyed by the typed id) -- GetBaseSpell can map a KNOWN
        -- spell to a different base id, severing the entry from its tag (e.g. 193265 ->
        -- 56641, blank icon). Tagged entries keep the typed id; a base form that matches
        -- one heals back to its tagged custom id, self-repairing severed saved data.
        local customN = sd.customSpellIDs
        local customByBase
        if customN then
            for cid in pairs(customN) do
                if type(cid) == "number" and cid > 0 then
                    local checkBtn = NormalizeToBase(cid)
                    if checkBtn ~= cid then
                        customByBase = customByBase or {}
                        customByBase[checkBtn] = cid
                    end
                end
            end
        end
        local seen = {}
        -- WoW Forever: one entry per spell, whatever its rank (ns.CDMRankName):
        -- the first one listed stays where it is, a later rank of it goes.
        local RankName = mod.CDMRankName
        local seenRank = RankName and {}
        local rankCut = false
        local writeIdx = 1
        for readIdx = 1, #sd.assignedSpells do
            local raw = sd.assignedSpells[readIdx]
            local spellRef
            if customN and customN[raw] then
                spellRef = raw
            else
                spellRef = NormalizeToBase(raw)
                if customByBase and customByBase[spellRef] then
                    spellRef = customByBase[spellRef]
                end
            end
            if not seen[spellRef] then
                local name = seenRank and not (customN and customN[spellRef]) and RankName(spellRef)
                if name and seenRank[name] then
                    rankCut = true
                else
                    seen[spellRef] = true
                    if name then
                        seenRank[name] = true
                    end
                    sd.assignedSpells[writeIdx] = spellRef
                    writeIdx = writeIdx + 1
                end
            end
        end
        for idx = writeIdx, #sd.assignedSpells do
            sd.assignedSpells[idx] = nil
        end
        if rankCut then
            mod._spellOrderDirty = true
        end
    end
    -- Append any live-bar spells missing from assignedSpells so the preview always
    -- matches the player's CDM bars (e.g. after re-talenting). EXCEPTION: skip while an
    -- imported layout is pending its first-load ghosting (_importGhostMode). Imported
    -- tracked spells spill onto default bars until migration ghosts them; materializing
    -- them here would mark them "assigned" and permanently defeat import-authoritative
    -- ghosting -- the import happens FROM this panel, so this rebuild fires before migration runs; the gate is essential.
    local importPending = false
    do
        local specProfiles = mod.GetActiveSpecProfiles and mod.GetActiveSpecProfiles()
        local sk = mod.GetActiveSpecKey and mod.GetActiveSpecKey()
        local aprof = specProfiles and sk and specProfiles[sk]
        if aprof and aprof._importGhostMode then
            importPending = true
        end
    end
    -- Buff-family bars get buffs ONLY through the picker (ShowBuffBarPicker ->
    -- AddTrackedSpell); assignedSpells is already authoritative, nothing legitimately
    -- spills onto them. Skipping the live-icon append for them fixes the duplicate-slot
    -- bug: a buff's resolved spellID drifts between ACTIVE (GetSpellID/GetAuraSpellID
    -- secret -> fallback) and INACTIVE (clean GetAuraSpellID), so post-combat the live
    -- icon can resolve to a different ID than stored and re-add the same buff. CD/utility bars still need the append (re-talent repop + spillover reconciliation).
    local bdForFamily = mod.barDataByKey and mod.barDataByKey[barKeyE]
    local isBuffFamilyE = mod.IsBarBuffFamily and mod.IsBarBuffFamily(bdForFamily or barKeyE)
    local liveIcons = not importPending and not isBuffFamilyE and mod.cdmBarIcons and mod.cdmBarIcons[barKeyE]
    if liveIcons then
        if not sd.assignedSpells then
            sd.assignedSpells = {}
        end
        local removed = sd.removedSpells
        -- Never materialize a spell currently HIDDEN (in the ghost bar) onto a visible
        -- bar -- that recreates a both-state and the spell would reappear. Variant-aware
        -- against the active spec's ghost list; closes the window between migration ghosting a spell and the reanchor refreshing cdmBarIcons.
        local ghostSd = mod.GetBarSpellData and mod.GetBarSpellData("__ghost_cd")
        local ghostList = ghostSd and ghostSd.assignedSpells
        local FindVar = mod.FindVariantIndexInList
        -- Never materialize a spell the user deliberately placed on ANOTHER bar: a
        -- transient spillover during a profile swap can briefly render a custom-bar
        -- spell on cooldowns, and appending it here creates a both-state the route map
        -- must arbitrate. Claimed set built from the active spec's STORED bars, not the live route map (momentarily stale during the swap).
        local claimedElsewhere
        do
            local specProfiles = mod.GetActiveSpecProfiles and mod.GetActiveSpecProfiles()
            local sk = mod.GetActiveSpecKey and mod.GetActiveSpecKey()
            local aprof = specProfiles and sk and specProfiles[sk]
            local bsAll = aprof and aprof.barSpells
            if bsAll and mod.StoreVariantValue then
                for key, bsd in pairs(bsAll) do
                    if
                        key ~= barKeyE
                        and key ~= "__ghost_cd"
                        and type(bsd) == "table"
                        and type(bsd.assignedSpells) == "table"
                    then
                        for _, spellRef in ipairs(bsd.assignedSpells) do
                            if type(spellRef) == "number" and spellRef > 0 then
                                claimedElsewhere = claimedElsewhere or {}
                                mod.StoreVariantValue(claimedElsewhere, spellRef, true, false)
                            end
                        end
                    end
                end
            end
        end
        -- Walk live icons in on-screen order (CollectAndReanchor already placed
        -- spillover cooldowns at their Blizzard-layout positions). A new spell inserts
        -- after its left neighbour so it takes its true Blizzard-CDM position;
        -- appending at the end piled talent-swap spells after trinket/racial slots and
        -- never survived /reload. Presence check AND position cursor must be
        -- variant-aware (mirrors the reseed pass in CUI_CDM_Reconcile.lua): an
        -- exact-match set misses a stored entry with a different variant form, re-inserting a duplicate the normalize pass above then dedupes by deleting the saved slot.
        local insertPos = nil
        for _, icon in ipairs(liveIcons) do
            -- Resolve the live icon's DISPLAYED spell the same way the picker does
            -- (canonical = GetSpellID-first, active-frame cache), so a spell whose
            -- cooldownInfo base differs from its live talent form (e.g. 137029 Holy
            -- Paladin vs 432496 Holy Bulwark) dedups against the stored canonical ID
            -- instead of appending a duplicate. Falls back to raw FC spellID for our own custom frames.
            local _sid = (mod.GetCanonicalSpellIDForFrame and mod.GetCanonicalSpellIDForFrame(icon))
                or (mod._ecmeFC[icon] and mod._ecmeFC[icon].spellID)
            -- Skip hosted-buff frames and their placeholders: their bar membership is
            -- the hosted MARKER entry; materializing their canonical spellID here would fabricate a plain COOLDOWN entry for the same spell (the buff frame's id resolves positive).
            local _fdLI = mod._hookFrameData and mod._hookFrameData[icon]
            if icon._isPlaceholderFrame or (_fdLI and _fdLI._isBuffViewerFrame) then
                -- Advance the cursor over the hosted buff's MARKER entry so a spell
                -- inserted after it lands after the buff, not squeezed beside the previous CD spell (mirrors the reseed pass).
                if
                    type(_sid) == "number"
                    and _sid > 0
                    and mod.HostedBuffMarkerToSpell
                    and not (mod.CdmFrameOverflowBar and mod.CdmFrameOverflowBar(icon))
                then
                    for idx = 1, #sd.assignedSpells do
                        local dec = mod.HostedBuffMarkerToSpell(sd.assignedSpells[idx])
                        if dec and (dec == _sid or (mod.IsVariantOf and mod.IsVariantOf(dec, _sid))) then
                            if not insertPos or idx > insertPos then
                                insertPos = idx
                            end
                            break
                        end
                    end
                end
                _sid = nil
            end
            -- Skip overflow-diverted icons: session-only here but BELONG to their
            -- source bar's assignedSpells -- materializing them (or advancing the cursor) would write the diversion into this bar's saved list.
            if _sid and mod.CdmFrameOverflowBar and mod.CdmFrameOverflowBar(icon) then
                _sid = nil
            end
            if _sid and _sid ~= 0 then
                if _sid > 0 then
                    _sid = NormalizeToBase(_sid)
                end
                -- FindVar handles negatives by exact scan internally; variant matching is a superset of exact for positives.
                local at = FindVar and FindVar(sd.assignedSpells, _sid)
                if at then
                    -- Already has a slot (any variant form, or a custom trinket/item
                    -- marker): advance the cursor so the next NEW spell lands after it, matching on-screen order.
                    insertPos = at
                elseif
                    _sid > 0
                    and not (removed and removed[_sid])
                    and not (ghostList and FindVar and FindVar(ghostList, _sid))
                    and not (
                        claimedElsewhere
                        and mod.ResolveVariantValue
                        and mod.ResolveVariantValue(claimedElsewhere, _sid)
                    )
                then
                    -- No anchored predecessor yet: this new spell is the left-most live icon, so it belongs at the front.
                    local place = insertPos and (insertPos + 1) or 1
                    table.insert(sd.assignedSpells, place, _sid)
                    insertPos = place
                end
            end
        end
    end
    -- Materialize tracked-but-UNLEARNED CD/utility spells onto the DEFAULT bar of their
    -- category: Blizzard creates no viewer frame for an untalented spell, so the
    -- live-icon append above can never see them (without this they're invisible in the
    -- whole management UI). Sourced from the settings catalog
    -- (ns.EnumerateCDMSettingsCatalog), which respects the user's Blizzard arrangement:
    -- spells moved to Not Displayed never materialize, and each inserts after its
    -- nearest catalog predecessor already in the list. Guards, all load-bearing:  -- cui-style: allow comment-budget
    --   * default cooldowns/utility bars only (custom bars get spells via the picker)
    --   * LEARNED spells are the live-icon pass's job above (except one its
    --     Talent Conditions hide: no live icon, so it materializes here too)
    --   * skipped while import ghosting is pending, or before the spec's V6 ghost
    --     migration flag is stamped (ghosting must classify spells BEFORE materializing)
    --   * ghosted, explicitly-removed, and claimed-elsewhere spells skip
    --   * catalog nil (provider unavailable) = pass no-ops entirely
    if
        not importPending
        and (barKeyE == "cooldowns" or barKeyE == "utility")
        and mod.EnumerateCDMSettingsCatalog
    then
        local aprofM, migrated
        do
            local specProfiles = mod.GetActiveSpecProfiles and mod.GetActiveSpecProfiles()
            local sk = mod.GetActiveSpecKey and mod.GetActiveSpecKey()
            aprofM = specProfiles and sk and specProfiles[sk]
            migrated = aprofM and aprofM._barFilterModelV6 and true or false
        end
        local catalog = migrated and mod.EnumerateCDMSettingsCatalog() or nil
        if catalog and #catalog > 0 and IsPlayerSpell then
            local evc = Enum and Enum.CooldownViewerCategory
            -- Per-bar category wantSet, not a single wantCat value: a
            -- SpecAgnostic/EquipSlot cooldown entry (Midnight's category
            -- expansion) has no single category that could ever match a
            -- two-branch if/else, and would stay invisible to this
            -- materializer forever while untalented/unequipped.
            local wantSet
            if evc then
                if barKeyE == "cooldowns" then
                    -- EquipSlotEssential (7) deliberately absent: native
                    -- equipment entries are never claimed (the preset
                    -- slot/item lane owns items), so materializing their
                    -- rows would mint permanent frameless rank-holders.
                    wantSet = {
                        [evc.Essential or 0] = true,
                        [evc.SpecAgnosticEssential or 5] = true,
                    }
                else
                    wantSet = { [evc.Utility or 1] = true }
                end
            end
            local FindVar = mod.FindVariantIndexInList
            if wantSet and FindVar then
                if not sd.assignedSpells then
                    sd.assignedSpells = {}
                end
                local entries = sd.assignedSpells
                local removed = sd.removedSpells
                local ghostSdM = mod.GetBarSpellData and mod.GetBarSpellData("__ghost_cd")
                local ghostListM = ghostSdM and ghostSdM.assignedSpells
                -- Spells the user placed on ANY other bar keep their home.
                local claimedM
                do
                    local bsAll = aprofM and aprofM.barSpells
                    if bsAll and mod.StoreVariantValue then
                        for key, bsd in pairs(bsAll) do
                            if
                                key ~= barKeyE
                                and key ~= "__ghost_cd"
                                and type(bsd) == "table"
                                and type(bsd.assignedSpells) == "table"
                            then
                                for _, spellRef in ipairs(bsd.assignedSpells) do
                                    if type(spellRef) == "number" and spellRef > 0 then
                                        claimedM = claimedM or {}
                                        mod.StoreVariantValue(claimedM, spellRef, true, false)
                                    end
                                end
                            end
                        end
                    end
                end
                -- A LEARNED spell whose Talent Conditions dropped it from this bar in the
                -- last reanchor has no live icon either: materialize it like an unlearned
                -- one, so it keeps (or regains, after Repopulate or a Blizzard untrack and
                -- retrack) a preview slot and its conditions stay reachable. The set is
                -- shared and empty for non-users, so the check is skipped for them.
                local tcHidden = mod.TalentCondHiddenSet(barKeyE)
                if not next(tcHidden) then
                    tcHidden = nil
                end
                for ci = 1, #catalog do
                    local ce = catalog[ci]
                    if wantSet[ce.category] then
                        local nsid = NormalizeToBase(ce.sid)
                        local isKnownM = true
                        if type(nsid) == "number" and nsid > 0 then
                            isKnownM = (
                                IsPlayerSpell(nsid)
                                or IsPlayerSpell(ce.sid)
                                or IsPlayerSpell(ResolveToLive(nsid))
                            )
                                    and true
                                or false
                            if
                                isKnownM
                                and tcHidden
                                and (
                                    mod.ResolveVariantValue(tcHidden, nsid)
                                    or mod.ResolveVariantValue(tcHidden, ce.sid)
                                )
                            then
                                isKnownM = false
                            end
                        end
                        if
                            type(nsid) == "number"
                            and nsid > 0
                            and not isKnownM
                            and not FindVar(entries, nsid)
                            and not (removed and (removed[nsid] or removed[ce.sid]))
                            and not (ghostListM and FindVar(ghostListM, nsid))
                            and not (
                                claimedM
                                and mod.ResolveVariantValue
                                and mod.ResolveVariantValue(claimedM, nsid)
                            )
                        then
                            local place
                            for cj = ci - 1, 1, -1 do
                                local prevSid = NormalizeToBase(catalog[cj].sid)
                                local at = FindVar(entries, prevSid)
                                if at then
                                    place = at
                                    break
                                end
                            end
                            if place then
                                table.insert(entries, place + 1, nsid)
                            else
                                table.insert(entries, 1, nsid)
                            end
                        end
                    end
                end
            end
        end
    end
    -- Reconcile stale generic variants: a buff whose cooldownInfo base spellID differs
    -- from its live talent form (e.g. 137029 Holy Paladin stored next to 432496 Holy
    -- Bulwark) leaves a generic duplicate that variant dedup cannot collapse (no
    -- GetBaseSpell/override link). Map each pooled buff frame's base spellID -> its
    -- canonical live spellID, then drop any stored base whose canonical form is ALSO present, never stranding a lone entry.
    if sd.assignedSpells and #sd.assignedSpells > 1 and mod.GetCanonicalSpellIDForFrame then
        local viewer = _G.BuffIconCooldownViewer
        local pool = viewer and viewer.itemFramePool
        if pool and pool.EnumerateActive then
            local canonOf
            for widget in pool:EnumerateActive() do
                local details = widget.cooldownInfo
                local baseSID = details and details.spellID
                local canon = mod.GetCanonicalSpellIDForFrame(widget)
                if type(baseSID) == "number" and baseSID > 0 and type(canon) == "number" and canon > 0 then
                    local nb, nc = NormalizeToBase(baseSID), NormalizeToBase(canon)
                    if nb ~= nc then
                        canonOf = canonOf or {}
                        canonOf[nb] = nc
                    end
                end
            end
            if canonOf then
                local present = {}
                for _, spellRef in ipairs(sd.assignedSpells) do
                    present[spellRef] = true
                end
                local writeIdx = 1
                for readIdx = 1, #sd.assignedSpells do
                    local spellRef = sd.assignedSpells[readIdx]
                    local canon = canonOf[spellRef]
                    if not (canon and present[canon]) then
                        sd.assignedSpells[writeIdx] = spellRef
                        writeIdx = writeIdx + 1
                    end
                end
                for idx = writeIdx, #sd.assignedSpells do
                    sd.assignedSpells[idx] = nil
                end
            end
        end
    end
    -- Keep/drop reconciliation now lives in the resident module (single
    -- implementation shared with the automatic reseed/settings-close
    -- triggers -- see ns.ReconcileAssignedSpellDrops in
    -- CUI_CDM_Reconcile.lua for the full decision ladder).
    if mod.ReconcileAssignedSpellDrops then
        sd = mod.ReconcileAssignedSpellDrops(barKeyE) or sd
    end
    -- Self-heal HOSTED buffs: a hosted buff must live in assignedSpells (Phase 3 sort
    -- keys off its MARKER entry), but a drop pass can strand one in hostedBuffSpellIDs
    -- alone (never in the Essential/Utility viewer). Re-append the MARKER when neither it nor a legacy plain entry represents the buff -- never the plain id, which would resurrect the spell's COOLDOWN form.
    if sd.hostedBuffSpellIDs and sd.assignedSpells and mod.HostedBuffMarker then
        for hsid in pairs(sd.hostedBuffSpellIDs) do
            if type(hsid) == "number" and hsid > 0 then
                local markerH = mod.HostedBuffMarker(hsid)
                local present = false
                for _, spellRef in ipairs(sd.assignedSpells) do
                    if spellRef == hsid or spellRef == markerH then
                        present = true
                        break
                    end
                end
                if not present then
                    sd.assignedSpells[#sd.assignedSpells + 1] = markerH
                    mod._spellOrderDirty = true
                end
            end
        end
    end
    return sd
end

-- The number-entry popups below share one look, built by these. A popup is a
-- dimmer over the whole screen (a click on it closes the popup) holding the
-- dialog panel, centred a little above the middle.
local function NewEntryDialog(popupName, width, height)
    local dimmer = CreateFrame("Frame", popupName .. "Dimmer", UIParent)
    dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
    dimmer:SetAllPoints(UIParent)
    dimmer:EnableMouse(true)
    dimmer:Hide()
    local shade = dimmer:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    shade:SetColorTexture(0, 0, 0, 0.25)
    dimmer:SetScript("OnMouseDown", function(self)
        self:Hide()
    end)
    local panel = CreateFrame("Frame", popupName, dimmer)
    panel:SetSize(width, height)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetFrameLevel(dimmer:GetFrameLevel() + 10)
    panel:EnableMouse(true)
    local fill = panel:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(0.062, 0.070, 0.082, 1)
    CludesUI.MakeRoundedBorder(panel, 1, 1, 1, 0.15, fill)
    return panel, dimmer
end

-- The dialog's white heading at its top (text optional: some popups set it
-- on every show).
local function NewDialogTitle(dialog, text)
    local env = mod._CDMO_OptEnv
    local heading = dialog:CreateFontString(nil, "OVERLAY")
    heading:SetFont(env.FONT_PATH, 14, env.GetCDMOptOutline())
    heading:SetPoint("TOP", dialog, "TOP", 0, -18)
    heading:SetTextColor(1, 1, 1, 1)
    if text then
        heading:SetText(text)
    end
    return heading
end

-- A centred digits-only entry box of up to maxLetters digits, focused on
-- show. The caller places it.
local function NewEntryBox(dialog, maxLetters)
    local env = mod._CDMO_OptEnv
    local boxFrame = CreateFrame("EditBox", nil, dialog)
    boxFrame:SetSize(180, 28)
    boxFrame:SetAutoFocus(true)
    boxFrame:SetNumeric(true)
    boxFrame:SetMaxLetters(maxLetters)
    boxFrame:SetFont(env.FONT_PATH, 13, env.GetCDMOptOutline())
    boxFrame:SetTextColor(1, 1, 1, 0.9)
    boxFrame:SetJustifyH("CENTER")
    local fill = boxFrame:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(0.060, 0.049, 0.037, 1)
    CludesUI.MakeRoundedBorder(boxFrame, 1, 1, 1, 0.12, fill)
    return boxFrame
end

-- One of the dialog's two bottom buttons: the primary one (accent coloured,
-- left of centre) or the plain one (grey, right of centre). Its caption
-- whitens under the cursor. The caller gives it its click.
local function NewDialogButton(dialog, caption, primary)
    local env = mod._CDMO_OptEnv
    local accR, accG, accB = CludesUI.GetAccentColor()
    local button = CreateFrame("Button", nil, dialog)
    button:SetSize(80, 28)
    local fill = button:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    local restR, restG, restB, restA
    if primary then
        button:SetPoint("BOTTOMRIGHT", dialog, "BOTTOM", -4, 16)
        fill:SetColorTexture(accR, accG, accB, 0.15)
        CludesUI.MakeRoundedBorder(button, accR, accG, accB, 0.3, fill)
        restR, restG, restB, restA = accR, accG, accB, 0.9
    else
        button:SetPoint("BOTTOMLEFT", dialog, "BOTTOM", 4, 16)
        fill:SetColorTexture(0.12, 0.12, 0.12, 0.5)
        CludesUI.MakeRoundedBorder(button, 1, 1, 1, 0.10, fill)
        restR, restG, restB, restA = 0.7, 0.7, 0.7, 0.8
    end
    local text = button:CreateFontString(nil, "OVERLAY")
    text:SetFont(env.FONT_PATH, 12, env.GetCDMOptOutline())
    text:SetPoint("CENTER")
    text:SetText(CludesUI.L(caption))
    text:SetTextColor(restR, restG, restB, restA)
    button:SetScript("OnEnter", function()
        text:SetTextColor(1, 1, 1, 1)
    end)
    button:SetScript("OnLeave", function()
        text:SetTextColor(restR, restG, restB, restA)
    end)
    return button
end

---------------------------------------------------------------------------
--  Custom Spell ID popup (ShowBuffBarPicker, ShowBuffToCDPicker, ShowSpellPicker),
--  on the shared input popup. onAdded(sid) runs after the customSpellIDs tag is
--  stored. withCharges (CD/utility) adds the Show Charges opt-in and rejects
--  spells the spell list already offers.
---------------------------------------------------------------------------
local CUSTOM_SPELL_NOTE = { r = 0.9, g = 0.3, b = 0.3 }

local function ShowCustomSpellIDPopup(barId, onAdded, withCharges)
    local function SpellOf(textValue)
        local spellRef = tonumber(textValue)
        return spellRef and spellRef > 0 and math.floor(spellRef) or nil
    end
    CludesUI:ShowInputPopup({
        title = CludesUI.L("Add Custom Spell"),
        -- Permanent red note (user request 2026-10-23): a custom spell lives
        -- outside Blizzard's Cooldown Manager, so its restrictions can keep it
        -- from working fully.
        message = CludesUI.L(
            "Use at your own risk: Blizzard restrictions can keep custom spells from working fully."
        ),
        messageColor = CUSTOM_SPELL_NOTE,
        messageSize = 11,
        placeholder = CludesUI.L("Spell ID"),
        numeric = true,
        maxLetters = 7,
        confirmText = CludesUI.L("Add"),
        -- "Show Charges" opt-in: a manually entered spell has no Blizzard charge
        -- frame, but its cast count can still be shown on request.
        checkbox = withCharges and CludesUI.L("Show Charges") or nil,
        validate = function(textValue)
            local spellRef = SpellOf(textValue)
            if not spellRef then
                return CludesUI.L("Enter a valid spell ID")
            end
            if not C_Spell.GetSpellName(spellRef) then
                return CludesUI.L("Unknown spell ID")
            end
            -- Variant-aware, mirroring AddTrackedSpell's own dedup. An exact-only
            -- check lets a variant-duplicate through, which AddTrackedSpell then
            -- silently refuses AFTER the custom tag below is written (orphaned
            -- tag, nothing rendered).
            local sd = barId and mod.GetBarSpellData(barId)
            if sd and sd.assignedSpells and mod.FindVariantIndexInList(sd.assignedSpells, spellRef) then
                return CludesUI.L("Already tracked")
            end
            -- A spell the spell list offers goes through the list: as a custom
            -- spell its menu would write settings its icon never reads.
            if withCharges and mod.IsCDMTrackedCooldown(spellRef) then
                return CludesUI.L("Pick this spell from the spell list")
            end
        end,
        onConfirm = function(textValue, showCharges)
            local spellRef = SpellOf(textValue)
            local sd = barId and mod.GetBarSpellData(barId)
            if sd then
                if not sd.customSpellIDs then
                    sd.customSpellIDs = {}
                end
                sd.customSpellIDs[spellRef] = true
                -- Set/clear explicitly so a re-add with the box unchecked can't leave a
                -- stale flag behind, and flip the runtime gate live.
                if withCharges then
                    if showCharges then
                        if not sd.customSpellForceCount then
                            sd.customSpellForceCount = {}
                        end
                        sd.customSpellForceCount[spellRef] = true
                        mod._cdmAnyCustomForceCount = true
                    elseif sd.customSpellForceCount then
                        sd.customSpellForceCount[spellRef] = nil
                    end
                end
            end
            if onAdded then
                onAdded(spellRef)
            end
        end,
    })
end

---------------------------------------------------------------------------
--  Custom Item ID popup (shared by ShowSpellPicker + ShowBuffBarPicker).
--  Item is stored as a negative marker (-itemID) so the item-preset path
--  renders icon/cooldown/count. onAdded runs after validation; the caller
--  handles AddTrackedSpell.
---------------------------------------------------------------------------
-- The add-by-number popups (Custom Item, Equipment Slot): a title, the
-- entry box with a grey placeholder, an optional live echo line under it
-- (spec.echo(line, n) paints it from the typed number), a red status line
-- that clears itself 2.5s after each message, Add and Cancel. spec.toMarker
-- (n, SetStatus) turns the typed number into the bar entry to add, or says
-- why not and returns nil; an entry already on the bar is refused. onAdded
-- gets the new entry.
local function ShowMarkerPopup(spec, barId, onAdded)
    local dialog = _G[spec.name]
    if not dialog then
        local env = mod._CDMO_OptEnv
        local font, outline = env.FONT_PATH, env.GetCDMOptOutline()
        local dimmer
        dialog, dimmer = NewEntryDialog(spec.name, 320, spec.height)

        local title = NewDialogTitle(dialog, CludesUI.L(spec.title))
        dialog._title = title

        local editBox = NewEntryBox(dialog, spec.maxLetters)
        editBox:SetPoint("TOP", title, "BOTTOM", 0, -16)

        local placeholder = editBox:CreateFontString(nil, "ARTWORK")
        placeholder:SetFont(font, 12, outline)
        placeholder:SetPoint("CENTER")
        placeholder:SetTextColor(0.5, 0.5, 0.5, 0.5)
        placeholder:SetText(CludesUI.L(spec.placeholder))
        dialog._editBox = editBox

        local echoLine
        if spec.echo then
            echoLine = dialog:CreateFontString(nil, "OVERLAY")
            echoLine:SetFont(font, 12, outline)
            echoLine:SetPoint("TOP", editBox, "BOTTOM", 0, -8)
            echoLine:SetWidth(320 - 24)
            echoLine:SetText("")
            dialog._nameLine = echoLine
        end
        editBox:SetScript("OnTextChanged", function(self)
            local text = self:GetText()
            placeholder:SetShown(text == "")
            if echoLine then
                spec.echo(echoLine, tonumber(text))
            end
        end)

        local status = dialog:CreateFontString(nil, "OVERLAY")
        status:SetFont(font, 11, outline)
        if echoLine then
            status:SetPoint("TOP", echoLine, "BOTTOM", 0, -4)
        else
            status:SetPoint("TOP", editBox, "BOTTOM", 0, -6)
        end
        status:SetTextColor(1, 0.3, 0.3, 1)
        status:SetText("")
        dialog._status = status
        dialog._statusTimer = nil

        dialog._addBtn = NewDialogButton(dialog, "Add", true)
        local cancelBtn = NewDialogButton(dialog, "Cancel", false)
        local function Close()
            dimmer:Hide()
        end
        cancelBtn:SetScript("OnClick", Close)
        dialog._cancelBtn = cancelBtn
        editBox:SetScript("OnEscapePressed", Close)

        dialog._dimmer = dimmer
        _G[spec.name] = dialog
    end

    local function SetStatus(textValue, red, green, blue)
        dialog._status:SetText(CludesUI.L(textValue))
        dialog._status:SetTextColor(red or 1, green or 0.3, blue or 0.3, 1)
        if dialog._statusTimer then
            dialog._statusTimer:Cancel()
        end
        if textValue ~= "" then
            dialog._statusTimer = C_Timer.NewTimer(2.5, function()
                dialog._status:SetText("")
            end)
        end
    end

    local function DoAdd()
        local marker = spec.toMarker(tonumber(dialog._editBox:GetText()), SetStatus)
        if not marker then
            return
        end
        local sd = mod.GetBarSpellData(barId)
        for _, existing in ipairs(sd and sd.assignedSpells or {}) do
            if existing == marker then
                SetStatus("Already tracked")
                return
            end
        end
        dialog._dimmer:Hide()
        if onAdded then
            onAdded(marker)
        end
    end

    dialog._addBtn:SetScript("OnClick", DoAdd)
    dialog._editBox:SetScript("OnEnterPressed", DoAdd)
    dialog._editBox:SetText("")
    dialog._status:SetText("")
    if dialog._nameLine then
        dialog._nameLine:SetText("")
    end
    mod.PadPopupOpen(dialog._dimmer, dialog, dialog._cancelBtn) -- controller cursor
    dialog._dimmer:Show()
    dialog._editBox:SetFocus()
end

-- An item by its ID, kept as -itemID. IDs under 100 are refused: -1 to -19
-- are the equipment slots. An item the client has not loaded yet is asked
-- for, and the user to try again.
local ITEM_POPUP = {
    name = "CUI_CDM_ItemIDPopup",
    height = 164,
    maxLetters = 9,
    title = "Add Custom Item",
    placeholder = "Item ID",
    toMarker = function(itemId, SetStatus)
        if not itemId or itemId < 100 then
            SetStatus("Enter a valid item ID")
            return nil
        end
        itemId = math.floor(itemId)
        if not C_Item.GetItemNameByID(itemId) then
            C_Item.RequestLoadItemDataByID(itemId)
            SetStatus("Loading item data, try again")
            return nil
        end
        return -itemId
    end,
}
local function ShowCustomItemIDPopup(barId, onAdded)
    ShowMarkerPopup(ITEM_POPUP, barId, onAdded)
end

---------------------------------------------------------------------------
--  Equipment Slot popup. Adds a slot-tracked entry (-slotID, the trinket -13/-14
--  encoding) so the icon follows whatever item is equipped there (e.g. slot 6 = belt +
--  its tinker). The name line echoes the typed slot (localized name + equipped item) so a bare number is confirmed before Add.
---------------------------------------------------------------------------
local SLOT_POPUP = {
    name = "CUI_CDM_SlotIDPopup",
    height = 184,
    maxLetters = 2,
    title = "Add Equipment Slot",
    placeholder = "Slot ID",
    -- The slot's name and what is in it now (green), or a red hint for a
    -- number that is not a slot.
    echo = function(line, slot)
        local slotName = slot and mod.INV_SLOT_NAMES[slot]
        if slotName then
            local itemId = GetInventoryItemID("player", slot)
            local itemName = itemId and C_Item.GetItemNameByID(itemId)
            line:SetTextColor(0.6, 1, 0.6, 1)
            line:SetText(slotName .. " - " .. (itemName or EMPTY or ""))
        elseif slot then
            line:SetTextColor(1, 0.4, 0.4, 0.9)
            line:SetText("Enter a slot ID from 1 to 19")
        else
            line:SetText("")
        end
    end,
    toMarker = function(slot, SetStatus)
        if not slot or not mod.INV_SLOT_NAMES[slot] then
            SetStatus("Enter a slot ID from 1 to 19")
            return nil
        end
        return -slot
    end,
}
local function ShowEquipmentSlotPopup(barId, onAdded)
    ShowMarkerPopup(SLOT_POPUP, barId, onAdded)
end

---------------------------------------------------------------------------
--  Shared by the buff pickers below: their menu frame, its dividers and
--  footer, and the step that sizes, places and opens it.
---------------------------------------------------------------------------

-- A picker already open closes first; true when it was open on this same
-- anchor, so the click only toggled it shut.
local function ClosePickerMenu(optionState, anchor)
    local open = optionState._spellPickerMenu
    if not (open and open:IsShown()) then
        return false
    end
    open:Hide()
    return open._anchorFrame == anchor and open._anchorGen == PoolGen(anchor)
end

-- The picker's kept frame (one per poolKey for the session, dressed again on
-- each open) with its fill and border, and the inner frame its rows stack in.
local function NewPickerMenu(optionState, poolKey, width)
    local menu = PoolKept(optionState, poolKey, "Frame", UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(300)
    menu:SetClampedToScreen(true)
    menu:SetSize(width, 10)
    local fill = menu:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(
        CludesUI.DD_BG_R or 0.075,
        CludesUI.DD_BG_G or 0.113,
        CludesUI.DD_BG_B or 0.141,
        CludesUI.DD_BG_HA or 0.98
    )
    CludesUI.MakeRoundedBorder(menu, 1, 1, 1, CludesUI.DD_BRD_A or 0.20, fill, nil, true)
    local rows = CreateFrame("Frame", nil, menu)
    rows:SetWidth(width)
    rows:SetPoint("TOPLEFT")
    return menu, rows
end

-- A faint rule across the rows at height y; returns the height below it.
local function AddPickerDivider(rows, y)
    local rule = rows:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetColorTexture(1, 1, 1, 0.10)
    rule:SetPoint("TOPLEFT", rows, "TOPLEFT", 1, -y - 4)
    rule:SetPoint("TOPRIGHT", rows, "TOPRIGHT", -1, -y - 4)
    return y + 9
end

-- The two-line accent footer ("<question>" over "Add in Blizzard CDM") that
-- closes the picker and opens Blizzard's Cooldown Manager settings. Returns
-- the height below it.
local function AddBlizzardCDMFooter(menu, rows, y, question)
    local FOOTER_H = 38
    local env = mod._CDMO_OptEnv
    local footer = CreateFrame("Button", nil, rows)
    footer:SetHeight(FOOTER_H)
    footer:SetPoint("TOPLEFT", rows, "TOPLEFT", 1, -y)
    footer:SetPoint("TOPRIGHT", rows, "TOPRIGHT", -1, -y)
    footer:SetFrameLevel(menu:GetFrameLevel() + 2)
    local text = footer:CreateFontString(nil, "OVERLAY")
    text:SetFont(env.FONT_PATH, 11, env.GetCDMOptOutline())
    text:SetAllPoints()
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")
    local accR, accG, accB = CludesUI.GetAccentColor()
    text:SetTextColor(accR, accG, accB, 1)
    text:SetText(CludesUI.L(question) .. "\n" .. CludesUI.L("Add in Blizzard CDM"))
    footer:SetScript("OnEnter", function()
        text:SetTextColor(1, 1, 1, 1)
    end)
    footer:SetScript("OnLeave", function()
        local red, green, blue = CludesUI.GetAccentColor()
        text:SetTextColor(red, green, blue, 1)
    end)
    footer:SetScript("OnClick", function()
        menu:Hide()
        if mod.OpenBlizzardCDMTab then
            mod.OpenBlizzardCDMTab(true)
        end
    end)
    return y + FOOTER_H
end

-- Sizes the picker to its rows (scrolling past maxH), hangs it under the
-- anchor, records it as the open picker, and shows it; a left click
-- anywhere but the picker or its anchor closes it.
local function OpenPickerMenu(optionState, menu, rows, y, width, maxH, anchor)
    rows:SetHeight(y + 4)
    menu:SetSize(width, math.min(y + 4, maxH))
    if y + 4 > maxH then
        local scroller = CreateFrame("ScrollFrame", nil, menu)
        scroller:SetPoint("TOPLEFT", 0, -1)
        scroller:SetPoint("BOTTOMRIGHT", 0, 1)
        scroller:SetFrameLevel(menu:GetFrameLevel() + 1)
        scroller:EnableMouseWheel(true)
        scroller:SetScrollChild(rows)
        rows:SetWidth(width)
        CludesUI.AttachSmoothScrollbar(scroller, { step = 40, thumb = false })
    end
    menu:ClearAllPoints()
    menu:SetPoint("TOP", anchor, "BOTTOM", 0, -4)
    menu._anchorFrame = anchor
    menu._anchorGen = PoolGen(anchor)
    optionState._spellPickerMenu = menu
    menu:SetScript("OnUpdate", function(frame)
        if not frame:IsMouseOver() and not anchor:IsMouseOver() and IsMouseButtonDown("LeftButton") then
            frame:Hide()
        end
    end)
    menu:SetScript("OnHide", function(frame)
        frame:SetScript("OnUpdate", nil)
    end)
    menu:Show()
end

---------------------------------------------------------------------------
--  Buff Bar Spell Picker
--  Shows ONLY spells from CDM buff categories (2, 3).
--  None grayed out. Selecting moves the spell to the target bar.
---------------------------------------------------------------------------
local function ShowBuffBarPicker(anchor, targetBarKey, onChanged)
    local environ = mod._CDMO_OptEnv
    local FONT_PATH, GetCDMOptOutline, RefreshCDPreview, optionState =
        environ.FONT_PATH, environ.GetCDMOptOutline, environ.RefreshCDPreview, environ.optState
    if ClosePickerMenu(optionState, anchor) then
        return
    end

    local hlA = CludesUI.DD_ITEM_HL_A or 0.08
    local tDimR = CludesUI.DD_ITEM_R or 0.75
    local tDimG = CludesUI.DD_ITEM_G or 0.75
    local tDimB = CludesUI.DD_ITEM_B or 0.75
    local tDimA = CludesUI.DD_ITEM_A or 0.9
    local menuW = 240
    local ITEM_H = 26
    local MAX_H = 350

    -- Use the same data source as CD/utility: GetCDMSpellsForBar
    local allSpells = mod.GetCDMSpellsForBar and mod.GetCDMSpellsForBar(targetBarKey, true) or {}

    -- Every buff spell is shown and every row is clickable. Clicking a spell routes
    -- AddTrackedSpell, whose family sweep removes the spell from every other
    -- buff-family bar (including the ghost hidden bar) before claiming it for the
    -- target. Same model as CD/utility bars: one click, one move.
    local knownSpells = {}
    for _, sp in ipairs(allSpells) do
        if sp.cdmCatGroup == "buff" then
            knownSpells[#knownSpells + 1] = sp
        end
    end

    -- No early-out on an empty Blizzard buff list: preset buffs (and, later,
    -- a custom spell ID) are always available below.

    -- Build menu (one kept frame for the session, dressed again on every open)
    local dropMenu, inner = NewPickerMenu(optionState, "buffBarPicker", menuW)

    local menuH = 4

    -- Helper: create a spell row
    local function MakeSpellRow(sp)
        local entry = CreateFrame("Button", nil, inner)
        entry:SetHeight(ITEM_H)
        entry:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -menuH)
        entry:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -menuH)
        entry:SetFrameLevel(dropMenu:GetFrameLevel() + 2)

        local iconTex = entry:CreateTexture(nil, "ARTWORK")
        iconTex:SetSize(ITEM_H - 4, ITEM_H - 4)
        iconTex:SetPoint("LEFT", 4, 0)
        iconTex:SetTexture(sp.icon)
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local labelFS = entry:CreateFontString(nil, "OVERLAY")
        labelFS:SetFont(FONT_PATH, 11, GetCDMOptOutline())
        labelFS:SetPoint("LEFT", iconTex, "RIGHT", 6, 0)
        labelFS:SetPoint("RIGHT", -4, 0)
        labelFS:SetJustifyH("LEFT")
        labelFS:SetText(CludesUI.L(sp.name or ""))
        labelFS:SetTextColor(tDimR, tDimG, tDimB, tDimA)

        local highlight = entry:CreateTexture(nil, "ARTWORK")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0)

        -- Tracked-but-untalented buffs stay fully clickable but render
        -- desaturated with a hint, matching the CD/utility picker, so bars
        -- can be arranged without swapping talents.
        local notLearned = (sp.isKnown == false)
        if notLearned then
            iconTex:SetDesaturated(true)
            iconTex:SetAlpha(0.5)
        end

        entry:SetScript("OnEnter", function()
            labelFS:SetTextColor(1, 1, 1, 1)
            highlight:SetColorTexture(1, 1, 1, hlA)
            if notLearned then
                CludesUI.ShowWidgetTooltip(entry, CludesUI.L("Not currently talented"))
            end
        end)
        entry:SetScript("OnLeave", function()
            labelFS:SetTextColor(tDimR, tDimG, tDimB, tDimA)
            highlight:SetColorTexture(1, 1, 1, 0)
            if notLearned then
                CludesUI.HideWidgetTooltip()
            end
        end)

        -- Gray the row in place and make it inert. Called after the user
        -- clicks it to add the buff, so the picker can stay open for adding
        -- several buffs in a row.
        entry._grayOut = function()
            labelFS:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
            iconTex:SetDesaturated(true)
            iconTex:SetAlpha(0.4)
            highlight:SetColorTexture(1, 1, 1, 0)
            if notLearned then
                CludesUI.HideWidgetTooltip()
            end
            entry:SetScript("OnEnter", nil)
            entry:SetScript("OnLeave", nil)
            entry:SetScript("OnClick", nil)
        end

        menuH = menuH + ITEM_H
        return entry
    end

    -- Custom Spell ID entry -- add an arbitrary buff by spell ID, tracked
    -- as a real aura (12.1 engine slot; no duration asked). Entries that
    -- carry a stored duration are legacy cast-timer customs and keep that
    -- path untouched. Its own section at the top, matching the CD/utility
    -- picker.
    do
        local csItem = CreateFrame("Button", nil, inner)
        csItem:SetHeight(ITEM_H)
        csItem:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -menuH)
        csItem:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -menuH)
        csItem:SetFrameLevel(dropMenu:GetFrameLevel() + 2)
        local csHl = csItem:CreateTexture(nil, "ARTWORK")
        csHl:SetAllPoints()
        csHl:SetColorTexture(1, 1, 1, 0)
        csHl:SetAlpha(0)
        local csLbl = csItem:CreateFontString(nil, "OVERLAY")
        csLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
        csLbl:SetPoint("LEFT", 10, 0)
        csLbl:SetJustifyH("LEFT")
        csLbl:SetText(CludesUI.L("Custom Spell ID"))
        csLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
        csItem:SetScript("OnEnter", function()
            csLbl:SetTextColor(1, 1, 1, 1)
            csHl:SetColorTexture(1, 1, 1, hlA)
            csHl:SetAlpha(1)
        end)
        csItem:SetScript("OnLeave", function()
            csLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
            csHl:SetAlpha(0)
        end)
        csItem:SetScript("OnClick", function()
            dropMenu:Hide()
            ShowCustomSpellIDPopup(targetBarKey, function(spellRef)
                mod.AddTrackedSpell(targetBarKey, spellRef)
                if mod.RebuildSpellRouteMap then
                    mod.RebuildSpellRouteMap()
                end
                if mod.UpdateLustListener then
                    mod.UpdateLustListener()
                end
                if mod.UpdateCustomBuffAuraTracking then
                    mod.UpdateCustomBuffAuraTracking()
                end
                if mod.QueueReanchor then
                    mod.QueueReanchor()
                end
                RefreshCDPreview()
            end)
        end)
        menuH = menuH + ITEM_H
    end

    -- NOTE: No "Custom Item ID" entry here. Buff bars track auras only (spell
    -- IDs); items (stored as negative -itemID markers) belong on CD/utility
    -- bars. The cdm_strip_buff_bar_item_ids_v1 migration removes any legacy
    -- item markers that were placed on buff bars before this restriction.

    -- Divider below Custom Spell ID, separating it from the presets/list.
    do
        menuH = AddPickerDivider(inner, menuH)
    end

    -- Preset buffs (potions, consumables, Bloodlust, etc.) added as cast-timer
    -- custom buffs via AddPresetToBar; the buff phase injects an own-frame so
    -- they render alongside Blizzard-tracked buffs. The row count also gates
    -- the two dividers below, so an empty preset list (WoW Forever) never
    -- leaves two dividers back to back.
    local nPresetRows = 0
    do
        local _, _pClass = UnitClass("player")
        for _, preset in ipairs(mod.BUFF_BAR_PRESETS or {}) do
            if
                (not preset.class or preset.class == _pClass)
                and (not preset.tbbOnly or preset.customAuraToo)
            then
                local isAdded = mod.IsPresetOnBar(targetBarKey, preset)
                local si = CreateFrame("Button", nil, inner)
                si:SetHeight(ITEM_H)
                si:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -menuH)
                si:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -menuH)
                si:SetFrameLevel(dropMenu:GetFrameLevel() + 2)
                local sIco = si:CreateTexture(nil, "ARTWORK")
                sIco:SetSize(ITEM_H - 4, ITEM_H - 4)
                sIco:SetPoint("LEFT", 4, 0)
                sIco:SetTexture(CludesUI.ClientIcon(preset.icon))
                sIco:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                local sLbl = si:CreateFontString(nil, "OVERLAY")
                sLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                sLbl:SetPoint("LEFT", sIco, "RIGHT", 6, 0)
                sLbl:SetPoint("RIGHT", -4, 0)
                sLbl:SetJustifyH("LEFT")
                sLbl:SetWordWrap(false)
                sLbl:SetMaxLines(1)
                sLbl:SetText(CludesUI.L(preset.name or ""))
                local sHl = si:CreateTexture(nil, "ARTWORK")
                sHl:SetAllPoints()
                sHl:SetColorTexture(1, 1, 1, 0)
                if isAdded then
                    sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
                    sIco:SetDesaturated(true)
                    sIco:SetAlpha(0.4)
                else
                    sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                    si:SetScript("OnEnter", function()
                        sLbl:SetTextColor(1, 1, 1, 1)
                        sHl:SetColorTexture(1, 1, 1, hlA)
                    end)
                    si:SetScript("OnLeave", function()
                        sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                        sHl:SetColorTexture(1, 1, 1, 0)
                    end)
                    si:SetScript("OnClick", function()
                        EnsureAssignedSpells(targetBarKey)
                        mod.AddPresetToBar(targetBarKey, preset)
                        if mod.RebuildSpellRouteMap then
                            mod.RebuildSpellRouteMap()
                        end
                        if mod.UpdateLustListener then
                            mod.UpdateLustListener()
                        end
                        if mod.QueueReanchor then
                            mod.QueueReanchor()
                        end
                        RefreshCDPreview()
                        -- Keep the picker open so several buffs can be added
                        -- in a row; gray this preset in place once added.
                        sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
                        sIco:SetDesaturated(true)
                        sIco:SetAlpha(0.4)
                        sHl:SetColorTexture(1, 1, 1, 0)
                        si:SetScript("OnEnter", nil)
                        si:SetScript("OnLeave", nil)
                        si:SetScript("OnClick", nil)
                    end)
                end
                menuH = menuH + ITEM_H
                nPresetRows = nPresetRows + 1
            end
        end

        -- Divider between presets and the Blizzard-tracked buff list (none when
        -- no preset row was built: the Custom Spell ID divider already sits there).
        if #knownSpells > 0 and nPresetRows > 0 then
            menuH = AddPickerDivider(inner, menuH)
        end
    end

    do
        -- Pre-gray rows whose SLOT (cooldownID) is already tracked here: a
        -- collided pair renders two identical rows, and only the cd-level
        -- claim tells them apart.
        local sdRows = mod.GetBarSpellData(targetBarKey)
        local cdTracked = sdRows and mod.CollectCdClaimSet(sdRows)
        for _, sp in ipairs(knownSpells) do
            local entry = MakeSpellRow(sp)
            if cdTracked and sp.cdID and cdTracked[sp.cdID] then
                if entry._grayOut then
                    entry._grayOut()
                end
            else
                entry:SetScript("OnClick", function()
                    -- cdID rides along so collided buffs can be claimed per
                    -- viewer slot rather than per (shared) spellID.
                    if onChanged then
                        onChanged(sp.spellID, sp.cdID)
                    end
                    -- Keep the picker open so several buffs can be added in a
                    -- row; gray this row in place to reflect that it was added.
                    if entry._grayOut then
                        entry._grayOut()
                    end
                end)
            end
        end
    end

    -- "Missing Spells?" footer: centered, accent-colored prompt that opens
    -- Blizzard's CDM and closes CUI options, matching the CD/utility picker.
    -- Its divider is skipped when no row sits above it: the Custom Spell ID
    -- divider already separates the footer then.
    do
        if nPresetRows > 0 or #knownSpells > 0 then
            menuH = AddPickerDivider(inner, menuH)
        end

        menuH = AddBlizzardCDMFooter(dropMenu, inner, menuH, "Missing Spells?")
    end

    OpenPickerMenu(optionState, dropMenu, inner, menuH, menuW, MAX_H, anchor)
end

-- Buff picker targeting a CD/UTILITY bar. A buff placed here is HOSTED
-- (ns.AddBuffToCDUtilBar): Blizzard's own buff frame is diverted onto the bar, or a
-- greyed placeholder holds its slot while the aura is down. A Custom Spell ID
-- Blizzard does not track has no such frame, so an aura icon of ours draws it
-- (CUI_CDM_AuraIcons.lua). Lists the class's CDM-trackable buffs plus a Custom
-- Spell ID entry; no durations, item or preset rows.
-- onPicked(spellID, collidedCdID) = selection mode ("Replace with Buff"): every
-- catalog buff is listed, a "None" row clears, one click picks and closes, nothing is
-- hosted and there is no Custom Spell ID row (a replacement needs a Blizzard viewer
-- frame). Absent = the hosting picker below.
local function ShowBuffToCDPicker(anchor, targetBarKey, onChanged, onPicked)
    local environ = mod._CDMO_OptEnv
    local FONT_PATH, GetCDMOptOutline, optionState =
        environ.FONT_PATH, environ.GetCDMOptOutline, environ.optState
    if ClosePickerMenu(optionState, anchor) then
        return
    end

    local hlA = CludesUI.DD_ITEM_HL_A or 0.08
    local tDimR = CludesUI.DD_ITEM_R or 0.75
    local tDimG = CludesUI.DD_ITEM_G or 0.75
    local tDimB = CludesUI.DD_ITEM_B or 0.75
    local tDimA = CludesUI.DD_ITEM_A or 0.9
    local menuW = 240
    local ITEM_H = 26
    local MAX_H = 350

    -- Buff catalog comes from the default buffs bar (passing a CD/util barKey
    -- would return Essential/Utility spells). Dedup against buffs already
    -- HOSTED on this bar so re-opening the menu never re-lists an added
    -- buff. The hosted flag table is the membership truth (assignedSpells
    -- stores hosted buffs as negative markers, and a PLAIN id entry is the
    -- spell's COOLDOWN form -- which must not hide its buff form here).
    local allSpells = mod.GetCDMSpellsForBar and mod.GetCDMSpellsForBar("buffs", true) or {}
    local already = {}
    local sdCur = mod.GetBarSpellData(targetBarKey)
    if sdCur and sdCur.hostedBuffSpellIDs then
        for spellRef in pairs(sdCur.hostedBuffSpellIDs) do
            already[spellRef] = true
        end
    end
    -- Collided-buff slots (Diabolist Demonic Art vs Diabolic Ritual) are hosted by
    -- cooldownID, not by the shared spellID in `already` -- filter those out
    -- per-slot so only the specific claimed slot disappears, not both.
    local alreadyCd = sdCur and mod.CollectCdClaimSet(sdCur)
    -- Both modes skip buffs already HOSTED on this bar: a hosted buff owns a
    -- slot of its own, and doubling it as a replacement would leave that
    -- slot empty while the aura is active (Pass 3b and 3c would both route it).
    local knownSpells = {}
    for _, sp in ipairs(allSpells) do
        if
            sp.cdmCatGroup == "buff"
            and sp.spellID
            and not already[sp.spellID]
            and not (sp.cdID and alreadyCd and alreadyCd[sp.cdID])
        then
            knownSpells[#knownSpells + 1] = sp
        end
    end

    -- One kept frame for the session, dressed again on every open.
    local dropMenu, inner = NewPickerMenu(optionState, "buffToCDPicker", menuW)

    local menuH = 4

    -- Post-add refresh (picker stays open so several buffs add in a row): onChanged
    -- reanchors live bars and refreshes the preview in place. No RefreshCDPreview here --
    -- its full page rebuild orphans this still-open picker's anchor, so the next click falls onto the rebuilt preview slots and pops the per-icon settings dropdown uninvited.
    local function AfterAdd()
        if mod.RebuildSpellRouteMap then
            mod.RebuildSpellRouteMap()
        end
        if mod.QueueReanchor then
            mod.QueueReanchor()
        end
        if onChanged then
            onChanged()
        end
    end

    -- Custom Spell ID (no duration -- aura-driven). Selection mode gets a
    -- "None" row in this seat instead.
    do
        local csItem = CreateFrame("Button", nil, inner)
        csItem:SetHeight(ITEM_H)
        csItem:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -menuH)
        csItem:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -menuH)
        csItem:SetFrameLevel(dropMenu:GetFrameLevel() + 2)
        local csHl = csItem:CreateTexture(nil, "ARTWORK")
        csHl:SetAllPoints()
        csHl:SetColorTexture(1, 1, 1, 0)
        csHl:SetAlpha(0)
        local csLbl = csItem:CreateFontString(nil, "OVERLAY")
        csLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
        csLbl:SetPoint("LEFT", 10, 0)
        csLbl:SetJustifyH("LEFT")
        csLbl:SetText(onPicked and CludesUI.L("None (use cooldown icon)") or CludesUI.L("Custom Spell ID"))
        csLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
        csItem:SetScript("OnEnter", function()
            csLbl:SetTextColor(1, 1, 1, 1)
            csHl:SetColorTexture(1, 1, 1, hlA)
            csHl:SetAlpha(1)
        end)
        csItem:SetScript("OnLeave", function()
            csLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
            csHl:SetAlpha(0)
        end)
        csItem:SetScript("OnClick", function()
            dropMenu:Hide()
            if onPicked then
                onPicked(nil, nil)
                return
            end
            ShowCustomSpellIDPopup(targetBarKey, function(spellRef)
                mod.AddBuffToCDUtilBar(targetBarKey, spellRef)
                AfterAdd()
            end)
        end)
        menuH = menuH + ITEM_H
    end

    -- Divider below Custom Spell ID.
    do
        menuH = AddPickerDivider(inner, menuH)
    end

    -- Class buff rows.
    local function MakeSpellRow(sp)
        local entry = CreateFrame("Button", nil, inner)
        entry:SetHeight(ITEM_H)
        entry:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -menuH)
        entry:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -menuH)
        entry:SetFrameLevel(dropMenu:GetFrameLevel() + 2)
        local iconTex = entry:CreateTexture(nil, "ARTWORK")
        iconTex:SetSize(ITEM_H - 4, ITEM_H - 4)
        iconTex:SetPoint("LEFT", 4, 0)
        iconTex:SetTexture(sp.icon)
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local labelFS = entry:CreateFontString(nil, "OVERLAY")
        labelFS:SetFont(FONT_PATH, 11, GetCDMOptOutline())
        labelFS:SetPoint("LEFT", iconTex, "RIGHT", 6, 0)
        labelFS:SetPoint("RIGHT", -4, 0)
        labelFS:SetJustifyH("LEFT")
        labelFS:SetWordWrap(false)
        labelFS:SetMaxLines(1)
        labelFS:SetText(CludesUI.L(sp.name or ""))
        labelFS:SetTextColor(tDimR, tDimG, tDimB, tDimA)
        local highlight = entry:CreateTexture(nil, "ARTWORK")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0)
        -- Tracked-but-untalented buffs: desaturate + hint, still clickable (AddBuffToCDUtilBar has no learned gate; routes when talented).
        local notLearned = (sp.isKnown == false)
        if notLearned then
            iconTex:SetDesaturated(true)
            iconTex:SetAlpha(0.5)
        end
        entry:SetScript("OnEnter", function()
            labelFS:SetTextColor(1, 1, 1, 1)
            highlight:SetColorTexture(1, 1, 1, hlA)
            if notLearned then
                CludesUI.ShowWidgetTooltip(entry, CludesUI.L("Not currently talented"))
            end
        end)
        entry:SetScript("OnLeave", function()
            labelFS:SetTextColor(tDimR, tDimG, tDimB, tDimA)
            highlight:SetColorTexture(1, 1, 1, 0)
            if notLearned then
                CludesUI.HideWidgetTooltip()
            end
        end)
        entry:SetScript("OnClick", function()
            if notLearned then
                CludesUI.HideWidgetTooltip()
            end
            if onPicked then
                -- Selection mode: hand back the identity the runtime routes by
                -- (cooldownID for a collided pair or tracked trinket row, else the spellID) and close.
                local cdPick = mod.ClaimBuffByCdID(sp.spellID, sp.cdID) and sp.cdID or nil
                dropMenu:Hide()
                onPicked(sp.spellID, cdPick)
                return
            end
            -- Collided pair (two viewer slots, one shared spellID) or tracked trinket row: claim
            -- by cooldownID so each slot is hostable on its own; other buffs keep the sid path (identity survives talent swaps, cooldownIDs drift).
            if mod.ClaimBuffByCdID(sp.spellID, sp.cdID) then
                mod.AddHostedBuffByCdID(targetBarKey, sp.cdID, sp.spellID)
            else
                mod.AddBuffToCDUtilBar(targetBarKey, sp.spellID)
            end
            AfterAdd()
            -- Gray this row in place; keep the picker open.
            labelFS:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
            iconTex:SetDesaturated(true)
            iconTex:SetAlpha(0.4)
            highlight:SetColorTexture(1, 1, 1, 0)
            entry:SetScript("OnEnter", nil)
            entry:SetScript("OnLeave", nil)
            entry:SetScript("OnClick", nil)
        end)
        menuH = menuH + ITEM_H
        return entry
    end
    for _, sp in ipairs(knownSpells) do
        MakeSpellRow(sp)
    end

    -- "Missing Buffs?" footer -- opens Blizzard's CDM to Display more buffs.
    do
        menuH = AddPickerDivider(inner, menuH)

        menuH = AddBlizzardCDMFooter(dropMenu, inner, menuH, "Missing Buffs?")
    end

    OpenPickerMenu(optionState, dropMenu, inner, menuH, menuW, MAX_H, anchor)
end

-- The one-number popups (a title, a grey hint, the entry box, Save and
-- Cancel). spec gives the popup's global name, its height (default 150),
-- the digits allowed, its default title and hint (a caller may pass its own,
-- already localized; both are set on every show), decorate(dialog, box) for
-- anything drawn between the box and the buttons, and accept(n), which takes
-- the typed number (nil when empty) and returns whether to save and what to
-- hand onConfirm. Enter saves as Save does; Escape, Cancel or a click on the
-- dimmer close without saving.
local function ShowValuePopup(spec, current, onConfirm, title, hint)
    local dialog = _G[spec.name]
    if not dialog then
        local env = mod._CDMO_OptEnv
        local dimmer
        dialog, dimmer = NewEntryDialog(spec.name, 300, spec.height or 150)
        dialog._dimmer = dimmer

        local titleFS = NewDialogTitle(dialog)
        dialog._title = titleFS

        local hintFS = dialog:CreateFontString(nil, "OVERLAY")
        hintFS:SetFont(env.FONT_PATH, 11, env.GetCDMOptOutline())
        hintFS:SetPoint("TOP", titleFS, "BOTTOM", 0, -6)
        hintFS:SetTextColor(0.7, 0.7, 0.7, 0.85)
        dialog._hint = hintFS

        local boxFrame = NewEntryBox(dialog, spec.maxLetters)
        boxFrame:SetPoint("TOP", hintFS, "BOTTOM", 0, -12)
        dialog._box = boxFrame
        if spec.decorate then
            spec.decorate(dialog, boxFrame)
        end

        local saveBtn = NewDialogButton(dialog, "Save", true)
        local cancelBtn = NewDialogButton(dialog, "Cancel", false)
        local function Close()
            dimmer:Hide()
        end
        cancelBtn:SetScript("OnClick", Close)
        dialog._cancelBtn = cancelBtn

        local function Save()
            local accepted, value = spec.accept(tonumber(boxFrame:GetText()))
            if not accepted then
                return
            end
            dimmer:Hide()
            if dialog._onConfirm then
                dialog._onConfirm(value)
            end
        end
        saveBtn:SetScript("OnClick", Save)
        boxFrame:SetScript("OnEnterPressed", Save)
        boxFrame:SetScript("OnEscapePressed", Close)
    end
    dialog._onConfirm = onConfirm
    dialog._title:SetText(title or CludesUI.L(spec.title))
    dialog._hint:SetText(hint or CludesUI.L(spec.hint))
    dialog._box:SetText(current and tostring(current) or "")
    mod.PadPopupOpen(dialog._dimmer, dialog, dialog._cancelBtn) -- controller cursor
    dialog._dimmer:Show()
    dialog._box:SetFocus()
    dialog._box:HighlightText()
end

-- How long a preset icon's custom Active State shows: any positive seconds.
local DURATION_POPUP = {
    name = "CUI_CDM_DurationPopup",
    maxLetters = 5,
    title = "Active State Duration",
    hint = "Seconds the active state shows after use",
    accept = function(n)
        return n ~= nil and n > 0, n
    end,
}
local function ShowDurationPopup(currentVal, onConfirm)
    ShowValuePopup(DURATION_POPUP, currentVal, onConfirm)
end

-- An opacity percent, 1 to 100, whole: the "Lower Alpha (On CD)" effect's
-- by default, or the caller's (the Blackout glow opacity, for one).
local ALPHA_POPUP = {
    name = "CUI_CDM_AlphaPopup",
    maxLetters = 3,
    title = "Lower Alpha",
    hint = "Icon opacity while on cooldown (1-100%)",
    accept = function(n)
        return n ~= nil and n >= 1 and n <= 100, n and math.floor(n)
    end,
}
local function ShowAlphaPopup(currentPct, onConfirm, title, hint)
    ShowValuePopup(ALPHA_POPUP, currentPct, onConfirm, title, hint)
end

-- Whole seconds, 0 to 59 (0 turns it off): Threshold Seconds, the point
-- below which Threshold Color and Threshold Decimals apply, by default, or
-- the caller's (Also Show Below, for one).
local THRESHOLD_POPUP = {
    name = "CUI_CDM_ThresholdSecondsPopup",
    maxLetters = 2,
    title = "Threshold Seconds",
    hint = "Seconds left when threshold text starts (0 = off)",
    accept = function(n)
        return n ~= nil and n >= 0 and n <= 59, n and math.floor(n)
    end,
}
local function ShowThresholdSecondsPopup(currentVal, onConfirm, title, hint)
    ShowValuePopup(THRESHOLD_POPUP, currentVal, onConfirm, title, hint)
end

-- A spell's Custom Icon: the texture fileID shown for it in every form it
-- takes. Always saves: a positive ID as a whole number, empty or 0 as nil
-- (the override removed). Under the box, a preview of the typed ID (the
-- question mark while it is empty or not a usable ID), so a typo shows
-- before saving. On mod rather than a page local: the 200-local cap.
local QUESTION_MARK_ICON = 134400
local CUSTOM_ICON_POPUP = {
    name = "CUI_CDM_CustomIconPopup",
    height = 196,
    maxLetters = 9,
    title = "Custom Icon",
    hint = "Icon ID always shown for this spell (empty removes)",
    decorate = function(dialog, boxFrame)
        local preview = dialog:CreateTexture(nil, "ARTWORK")
        preview:SetSize(30, 30)
        preview:SetPoint("TOP", boxFrame, "BOTTOM", 0, -10)
        preview:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        preview:SetTexture(QUESTION_MARK_ICON)
        dialog._prev = preview
        boxFrame:SetScript("OnTextChanged", function(widget)
            local id = tonumber(widget:GetText())
            preview:SetTexture((id and id > 0) and id or QUESTION_MARK_ICON)
        end)
    end,
    accept = function(n)
        if n and n > 0 then
            return true, math.floor(n)
        end
        return true, nil
    end,
}
mod.ShowCDMCustomIconPopup = function(currentID, onConfirm)
    ShowValuePopup(CUSTOM_ICON_POPUP, currentID, onConfirm)
end

-- Used by CUI_CooldownManager_Options.lua and SpellPicker_Options.lua
mod.CDMO_EnsureAssignedSpells = EnsureAssignedSpells
mod.CDMO_ShowAlphaPopup = ShowAlphaPopup
mod.CDMO_ShowBuffBarPicker = ShowBuffBarPicker
mod.CDMO_ShowBuffToCDPicker = ShowBuffToCDPicker
mod.CDMO_ShowCustomItemIDPopup = ShowCustomItemIDPopup
mod.CDMO_ShowCustomSpellIDPopup = ShowCustomSpellIDPopup
mod.CDMO_ShowDurationPopup = ShowDurationPopup
mod.CDMO_ShowEquipmentSlotPopup = ShowEquipmentSlotPopup
mod.CDMO_ShowThresholdSecondsPopup = ShowThresholdSecondsPopup
