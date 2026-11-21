if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_SpecOverrides_ListPage.lua
--
--  The management list page and Promote Override to Profile.
--  Reads the earlier Spec Overrides files through CUI_NS._soInternals.
-------------------------------------------------------------------------------
local _, CUI_NS = ...
CUI_NS = CUI_NS.__cuiCoreNS or CUI_NS -- standalone builds: the core's own table (CludesUI.lua)
local Inner = CUI_NS._soInternals
-- CludesUI_SpecOverrides.lua or an earlier Spec Overrides file failed to
-- load.
if not Inner or Inner.broken then return end
Inner.broken = true

local ACCENT_B, ACCENT_G, ACCENT_R = Inner.ACCENT_B, Inner.ACCENT_G, Inner.ACCENT_R
local BlacklistedFKey, CurrentSpecID, DeepCopy = Inner.BlacklistedFKey, Inner.CurrentSpecID, Inner.DeepCopy
local EntryHolderGroup, EntryOwning = Inner.EntryHolderGroup, Inner.EntryOwning
local FKeyLoaded, GetGroups, GetStore, GOLD_B =
    Inner.FKeyLoaded, Inner.GetGroups, Inner.GetStore, Inner.GOLD_B
local GOLD_G, GOLD_R, GroupById = Inner.GOLD_G, Inner.GOLD_R, Inner.GroupById
local HasRegisteredDefault, L, MatchOwnedFKey = Inner.HasRegisteredDefault, Inner.L, Inner.MatchOwnedFKey
local NIL_SENT, ReadLive, RebuildFKeyIndex = Inner.NIL_SENT, Inner.ReadLive, Inner.RebuildFKeyIndex
local RunRefreshers, SpecInAnyGroup, SpecName = Inner.RunRefreshers, Inner.SpecInAnyGroup, Inner.SpecName
local SpecStrandedOnEntry, SplitFKey = Inner.SpecStrandedOnEntry, Inner.SplitFKey
local WriteLive, GetUnlockStore = Inner.WriteLive, Inner.GetUnlockStore
local WriteDefaultValues, GetBmStore = Inner.WriteDefaultValues, Inner.GetBmStore
local GetCondBmStore, GetCondDmStore = Inner.GetCondBmStore, Inner.GetCondDmStore
local GetDmStore, IsTBBChildKey, LayerSkipsKey = Inner.GetDmStore, Inner.IsTBBChildKey, Inner.LayerSkipsKey
local Cond, EXCLUDED_CONTEXTS, RequestGoldWalk = Inner.Cond, Inner.EXCLUDED_CONTEXTS, Inner.RequestGoldWalk
local EnterGroupEdit, BuildEntryCrumb = Inner.EnterGroupEdit, Inner.BuildEntryCrumb

-- This file's copies of shared names; Set<Name> keeps every copy current
-- (the lists are built at the end of CludesUI_SpecOverrides.lua).
local _editGroup = nil
Inner.editGroupSetters[#Inner.editGroupSetters + 1] = function(v) _editGroup = v end
local _activeSpec = nil
Inner.activeSpecSetters[#Inner.activeSpecSetters + 1] = function(v) _activeSpec = v end

-------------------------------------------------------------------------------
--  Management list page ("Spec Overrides" tab under Profiles & Presets).
--  Purely a list: per group, each captured setting with Go To / Remove.
-------------------------------------------------------------------------------
local function TitleCase(text)
    local out = text:gsub("(%a[%w']*)", function(w) return w:sub(1, 1):upper() .. w:sub(2):lower() end)
    return out
end

local function BuildListRow(host, rowY, item)
    -- Options page pool (CludesUI_FramePool.lua): on a pool host these rows
    -- are reset and dressed again by the next build (the list builders below).
    local CreateFrame = CludesUI._Pool.CreateFrame
    local CONTENT_PAD = CludesUI.CONTENT_PAD or 40
    local line = CreateFrame("Frame", nil, host)
    line:SetSize(host:GetWidth() - CONTENT_PAD * 2, 36)
    line:SetPoint("TOPLEFT", host, "TOPLEFT", CONTENT_PAD, rowY)

    local label = CludesUI.MakeFont(line, 13, nil, 1, 1, 1, 0.9)
    label:SetPoint("LEFT", line, "LEFT", 20, 0)
    label:SetText(L(item.label or "?"))

    local trail = CludesUI.MakeFont(line, 11, nil, 1, 1, 1, 0.3)
    trail:SetPoint("LEFT", label, "RIGHT", 10, 0)
    -- Built from the entry's fields when it has a page, so a renamed module or
    -- tab label (or a client language switch) shows current names, not the
    -- baked crumb.
    local crumbText = item.page and BuildEntryCrumb(item.module, item.element, item.page, item.section)
        or item.crumb
    trail:SetText(crumbText and TitleCase(crumbText) or "")

    local function MakeBtn(text, xOff, w)
        local button = CreateFrame("Button", nil, line)
        button:SetSize(w or 110, 22)
        button:SetPoint("RIGHT", line, "RIGHT", xOff, 0)
        CludesUI.SolidTex(button, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
        local brd = CludesUI.MakeRoundedBorder(button, 1, 1, 1, 0.22)
        local caption = CludesUI.MakeFont(button, 11, nil, 1, 1, 1, 0.8)
        caption:SetPoint("CENTER")
        caption:SetText(L(text))
        return button, brd
    end

    -- One row serves BOTH stores: entries created by an editing-as-conditional
    -- session live in the conditional store and remove from it.
    local isCondEntry
    do
        local cst = Cond.GetStore()
        if cst then
            for _, record in ipairs(cst) do
                if record == item then
                    isCondEntry = true
                    break
                end
            end
        end
    end
    -- A conditional entry whose fkey a SPEC override also owns never applies at
    -- runtime: Cond.WriteValues skips spec-owned fkeys outside an editing session
    -- (the forSession gate), so the value shows while the session is open and is
    -- dropped the moment it closes. The row otherwise reads as live while doing
    -- nothing, which is the whole reason this is hard to diagnose -- name the
    -- owner instead of leaving the eviction silent.
    if isCondEntry then
        local ownerEntry
        for fieldKey in pairs(item.values and item.values.default or {}) do
            ownerEntry = EntryOwning(fieldKey)
            if ownerEntry then break end
        end
        if ownerEntry then
            local og = GroupById(ownerEntry.group)
            local warn = CludesUI.MakeFont(line, 11, nil, 1, 0.45, 0.45, 0.85)
            warn:SetPoint("LEFT", trail, "RIGHT", 10, 0)
            warn:SetText(string.format(L("held by '%s'"), (og and og.name) or "?"))
            local hit = CreateFrame("Frame", nil, line)
            hit:SetAllPoints(warn)
            hit:EnableMouse(true)
            hit:SetScript(
                "OnEnter",
                function(self)
                    CludesUI.ShowWidgetTooltip(
                        self,
                        L(
                            "A spec override owns this setting, so this conditional value never applies outside an editing session. Remove the spec override to let it through."
                        )
                    )
                end
            )
            hit:SetScript("OnLeave", function() CludesUI.HideWidgetTooltip() end)
        end
    end

    local removeBtn, rmBrd = MakeBtn("Remove Override", -20, 116)
    removeBtn:SetScript("OnEnter", function()
        if rmBrd and rmBrd.SetColor then rmBrd:SetColor(1, 0.35, 0.35, 0.8) end
    end)
    removeBtn:SetScript("OnLeave", function()
        if rmBrd and rmBrd.SetColor then rmBrd:SetColor(1, 1, 1, 0.22) end
    end)
    removeBtn:SetScript("OnClick", function()
        CludesUI:ShowConfirmPopup({
            title = isCondEntry and L("Remove Conditional Override") or L("Remove Spec Override"),
            message = string.format(
                L("Remove '%s'? The setting keeps its current live value."),
                item.label or "?"
            ),
            confirmText = L("Remove"),
            cancelText = L("Cancel"),
            onConfirm = function()
                local st = isCondEntry and Cond.GetStore() or GetStore()
                if st then
                    for i, record in ipairs(st) do
                        if record == item then
                            table.remove(st, i)
                            break
                        end
                    end
                end
                if isCondEntry then
                    Cond.RebuildIndex()
                else
                    RebuildFKeyIndex()
                end
                RequestGoldWalk()
                CludesUI:RefreshPage(true)
            end,
        })
    end)

    local go, goBrd = MakeBtn("Go to Setting", -144, 104)
    go:SetScript("OnEnter", function()
        if goBrd and goBrd.SetColor then goBrd:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.8) end
    end)
    go:SetScript("OnLeave", function()
        if goBrd and goBrd.SetColor then goBrd:SetColor(1, 1, 1, 0.22) end
    end)
    go:SetScript("OnClick", function()
        local mod = item.module
        if not mod then
            for fieldKey in pairs(item.values and item.values.default or {}) do
                mod = SplitFKey(fieldKey)
                break
            end
        end
        if mod and CludesUI:GetModuleTitle(mod) then
            CludesUI:SelectModule(mod)
            if item.page and CludesUI.SelectPage then CludesUI:SelectPage(item.page) end
        end
    end)

    return line, 38
end

-- Row for one STRANDED per-spec value (see SpecStrandedOnEntry): shows the spec
-- and the setting it silently overrides, with a per-value Remove returning the
-- spec to the shared default. Removal is the only possible action -- no editing
-- session can reach them.
local function BuildStrandedRow(host, rowY, item, specID)
    local CreateFrame = CludesUI._Pool.CreateFrame
    local CONTENT_PAD = CludesUI.CONTENT_PAD or 40
    local line = CreateFrame("Frame", nil, host)
    line:SetSize(host:GetWidth() - CONTENT_PAD * 2, 36)
    line:SetPoint("TOPLEFT", host, "TOPLEFT", CONTENT_PAD, rowY)

    local label = CludesUI.MakeFont(line, 13, nil, 1, 1, 1, 0.9)
    label:SetPoint("LEFT", line, "LEFT", 20, 0)
    label:SetText(SpecName(specID))

    local owner = GroupById(item.group)
    local trail = CludesUI.MakeFont(line, 11, nil, 1, 1, 1, 0.3)
    trail:SetPoint("LEFT", label, "RIGHT", 10, 0)
    trail:SetText(
        string.format(
            "%s  -  %s",
            L(item.label or "?"),
            string.format(L("held by '%s'"), (owner and owner.name) or "?")
        )
    )

    local removeBtn = CreateFrame("Button", nil, line)
    removeBtn:SetSize(116, 22)
    removeBtn:SetPoint("RIGHT", line, "RIGHT", -20, 0)
    CludesUI.SolidTex(removeBtn, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
    local rmBrd = CludesUI.MakeRoundedBorder(removeBtn, 1, 1, 1, 0.22)
    local rmLbl = CludesUI.MakeFont(removeBtn, 11, nil, 1, 1, 1, 0.8)
    rmLbl:SetPoint("CENTER")
    rmLbl:SetText(L("Remove Override"))
    removeBtn:SetScript("OnEnter", function()
        if rmBrd and rmBrd.SetColor then rmBrd:SetColor(1, 0.35, 0.35, 0.8) end
    end)
    removeBtn:SetScript("OnLeave", function()
        if rmBrd and rmBrd.SetColor then rmBrd:SetColor(1, 1, 1, 0.22) end
    end)
    removeBtn:SetScript("OnClick", function()
        CludesUI:ShowConfirmPopup({
            title = L("Remove Stranded Override"),
            message = string.format(
                L("Remove the stranded '%s' override for %s? The spec returns to the shared default."),
                item.label or "?",
                SpecName(specID)
            ),
            confirmText = L("Remove"),
            cancelText = L("Cancel"),
            onConfirm = function()
                item.values[specID] = nil
                CludesUI.SpecOverrides_Apply(_activeSpec or CurrentSpecID())
                RequestGoldWalk()
                CludesUI:RefreshPage(true)
            end,
        })
    end)

    return line, 38
end

-- Prunes entries whose owning group no longer exists. Entries with no group at
-- all (legacy captures) are kept.
local function PruneOrphanEntries()
    local storeTbl = GetStore()
    if not storeTbl then return false end
    local removed = false
    local touched
    -- Restore an entry's recorded defaults live before dropping it as an ORPHAN: the
    -- dead group's values may be the ones currently applied, and with the entry gone
    -- nothing would ever write the default back (residue becomes the permanent
    -- baseline). Loaded, non-blacklisted scalar paths only; excluded-context drops
    -- deliberately keep live as-is (those settings left the system).
    local function RestoreEntryDefaults(record)
        if not (record.values and record.values.default) then return end
        for fieldKey, def in pairs(record.values.default) do
            if not BlacklistedFKey(fieldKey) and FKeyLoaded(fieldKey) then
                local v = def
                if v == NIL_SENT then v = nil end
                -- Same defaults-backed nil-poison skip as WriteSpecValues.
                local nilPoison = (v == nil) and HasRegisteredDefault(fieldKey)
                local cur = ReadLive(fieldKey)
                if not nilPoison and type(v) ~= "table" and type(cur) ~= "table" and cur ~= v then
                    if WriteLive(fieldKey, v) then
                        local folder = SplitFKey(fieldKey)
                        if folder then
                            touched = touched or {}
                            touched[folder] = true
                        end
                    end
                end
            end
        end
    end
    for i = #storeTbl, 1, -1 do
        local record = storeTbl[i]
        local dropBtn = false
        if record.group ~= nil and not GroupById(record.group) then
            -- Dangling creator id: retag to a surviving holder like the delete
            -- flow does; drop (with live restore) only when no group holds
            -- values on the entry.
            local holder = EntryHolderGroup(record)
            if holder then
                record.group = holder.id
                removed = true
            else
                RestoreEntryDefaults(record)
                dropBtn = true
            end
        end
        -- Entries captured in contexts later excluded from the system (module-,
        -- page-, or section-scoped) drop wholesale so they stop applying and
        -- vanish from the management list.
        if not dropBtn and record.module then
            local ex = EXCLUDED_CONTEXTS[record.module]
            if ex == true then
                dropBtn = true
            elseif type(ex) == "table" and record.page then
                local pex = ex[record.page]
                if pex == true then
                    dropBtn = true
                elseif type(pex) == "table" and record.section and pex[record.section] then
                    dropBtn = true
                end
            end
        end
        -- Strip paths into blacklisted folders: legacy entries can carry
        -- Cooldown Manager paths, and applying those re-injects frozen per-spec
        -- spell data (cross-spec spells flashing on bars). An entry left with
        -- no paths is dropped entirely.
        if not dropBtn and record.values and record.values.default then
            local stripped = false
            for fieldKey in pairs(record.values.default) do
                if BlacklistedFKey(fieldKey) then
                    for _, m in pairs(record.values) do
                        if type(m) == "table" then m[fieldKey] = nil end
                    end
                    stripped = true
                end
            end
            if stripped then
                removed = true
                if not next(record.values.default) then dropBtn = true end
            end
        end
        if dropBtn then
            table.remove(storeTbl, i)
            removed = true
        end
    end
    -- Self-heal: on group-created entries, per-spec value maps for specs in NO group
    -- are phantoms (leftovers from membership edits / group deletes). They silently
    -- pin the spec off the defaults and are invisible in the management list (buckets
    -- show creator + member deviations only). Legacy pre-group entries (group == nil)
    -- keep their per-spec values: that is their model.
    local healed = false
    for _, record in ipairs(storeTbl) do
        if record.group ~= nil and record.values then
            for key in pairs(record.values) do
                if type(key) == "number" and not SpecInAnyGroup(key) then
                    record.values[key] = nil
                    healed = true
                end
            end
        end
    end
    if healed then
        removed = true
        -- Put the healed specs' live data back on the shared defaults. DEFERRED one
        -- frame: this runs from PLAYER_LOGIN and from inside the list-page build,
        -- where a synchronous Apply fires module refreshers (and can re-enter a page
        -- rebuild) mid-build. Safe to defer: PruneRedundantValues' live-guard refuses
        -- to GC a recorded default while live still differs, so nothing is lost.
        C_Timer.After(0, function() CludesUI.SpecOverrides_Apply(_activeSpec or CurrentSpecID()) end)
    end
    if touched then RunRefreshers(touched) end
    if removed then
        RebuildFKeyIndex()
        RequestGoldWalk()
    end
    return removed
end

--- Generic fork-management row (name + gold crumb + Delete behind a confirm
--- popup). opts: crumb, title, message ('%s' = group name), removeFn. Defaults
--- describe the unlock-layout fork.
local function BuildUnlockLayoutRow(host, rowY, group, opts)
    opts = opts or {}
    local crumbText = opts.crumb or "Custom Layout Mode"
    local heading = opts.title or "Delete Custom Layout Mode"
    local msgText = opts.message
        or "Delete the custom layout mode for '%s'? Its specs return to your default layout mode layout."
    local removeFn = opts.removeFn or CludesUI.SpecOverrides_RemoveUnlockLayout

    local CreateFrame = CludesUI._Pool.CreateFrame
    local CONTENT_PAD = CludesUI.CONTENT_PAD or 40
    local line = CreateFrame("Frame", nil, host)
    line:SetSize(host:GetWidth() - CONTENT_PAD * 2, 36)
    line:SetPoint("TOPLEFT", host, "TOPLEFT", CONTENT_PAD, rowY)

    local label = CludesUI.MakeFont(line, 13, nil, 1, 1, 1, 0.9)
    label:SetPoint("LEFT", line, "LEFT", 20, 0)
    label:SetText(group.name or "?")

    local trail = CludesUI.MakeFont(line, 11, nil, GOLD_R, GOLD_G, GOLD_B, 0.75)
    trail:SetPoint("LEFT", label, "RIGHT", 10, 0)
    trail:SetText(L(crumbText))

    local button = CreateFrame("Button", nil, line)
    button:SetSize(116, 22)
    button:SetPoint("RIGHT", line, "RIGHT", -20, 0)
    CludesUI.SolidTex(button, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
    local brd = CludesUI.MakeRoundedBorder(button, 1, 1, 1, 0.22)
    local caption = CludesUI.MakeFont(button, 11, nil, 1, 1, 1, 0.8)
    caption:SetPoint("CENTER")
    caption:SetText(L("Delete"))
    button:SetScript("OnEnter", function()
        if brd and brd.SetColor then brd:SetColor(1, 0.35, 0.35, 0.8) end
    end)
    button:SetScript("OnLeave", function()
        if brd and brd.SetColor then brd:SetColor(1, 1, 1, 0.22) end
    end)
    button:SetScript("OnClick", function()
        CludesUI:ShowConfirmPopup({
            title = L(heading),
            message = string.format(L(msgText), group.name or "?"),
            confirmText = L("Delete"),
            cancelText = L("Cancel"),
            onConfirm = function()
                if removeFn then removeFn(group.id) end
                CludesUI:RefreshPage(true)
            end,
        })
    end)

    -- Edit: opens the fork's OWN editing session, then jumps to its manager page.
    -- The session is load-bearing: the manager page prelude engages the fork only
    -- while a session is open, and Cond.ExitEdit is the sole release path, so the
    -- swap is never engaged directly here.
    if opts.editKind and opts.editPage then
        local record = CreateFrame("Button", nil, line)
        record:SetSize(116, 22)
        record:SetPoint("RIGHT", button, "LEFT", -8, 0)
        CludesUI.SolidTex(record, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
        local ebrd = CludesUI.MakeRoundedBorder(record, 1, 1, 1, 0.22)
        local elbl = CludesUI.MakeFont(record, 11, nil, 1, 1, 1, 0.8)
        elbl:SetPoint("CENTER")
        elbl:SetText(L("Edit"))
        record:SetScript("OnEnter", function()
            if ebrd and ebrd.SetColor then ebrd:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.8) end
        end)
        record:SetScript("OnLeave", function()
            if ebrd and ebrd.SetColor then ebrd:SetColor(1, 1, 1, 0.22) end
        end)
        record:SetScript("OnClick", function()
            -- Raid Frames must be registered to navigate to (same gate as the
            -- entry rows' Go to Setting).
            if not (CludesUI:GetModuleTitle("CludesUIRaidFrames")) then return end
            -- Both entry points refuse (own popup) when another fork holds the
            -- manager page; only navigate once the session actually opened.
            if opts.editKind == "cond" then
                if not Cond.EnterEdit then return end
                Cond.EnterEdit(group)
                if Cond._edit ~= group then return end
            else
                if not EnterGroupEdit then return end
                EnterGroupEdit(group)
                if _editGroup ~= group then return end
            end
            CludesUI:SelectModule("CludesUIRaidFrames")
            CludesUI:SelectPage(opts.editPage)
        end)
    end

    return line, 38
end

--- Row presets for the Buff Manager forks (spec + conditional variants).
local BM_ROW_SPEC = {
    crumb = "Custom Buff Manager",
    title = "Delete Custom Buff Manager",
    message = "Delete the custom Buff Manager for '%s'? Its specs return to your default Buff Manager.",
    removeFn = function(gid) CludesUI.SpecOverrides_RemoveBmLayout(gid) end,
    editKind = "spec",
    editPage = "Buff Manager",
}
local BM_ROW_COND = {
    crumb = "Custom Buff Manager",
    title = "Delete Custom Buff Manager",
    message = "Delete the custom Buff Manager for '%s'? Its conditions return to your default Buff Manager.",
    removeFn = function(gid) CludesUI.Conditions_RemoveBmLayout(gid) end,
    editKind = "cond",
    editPage = "Buff Manager",
}

--- Row presets for the Debuff Manager forks (spec + conditional variants).
local DM_ROW_SPEC = {
    crumb = "Custom Debuff Manager",
    title = "Delete Custom Debuff Manager",
    message = "Delete the custom Debuff Manager for '%s'? Its specs return to your default Debuff Manager.",
    removeFn = function(gid) CludesUI.SpecOverrides_RemoveDmLayout(gid) end,
    editKind = "spec",
    editPage = "Debuff Manager",
}
local DM_ROW_COND = {
    crumb = "Custom Debuff Manager",
    title = "Delete Custom Debuff Manager",
    message = "Delete the custom Debuff Manager for '%s'? Its conditions return to your default Debuff Manager.",
    removeFn = function(gid) CludesUI.Conditions_RemoveDmLayout(gid) end,
    editKind = "cond",
    editPage = "Debuff Manager",
}

-------------------------------------------------------------------------------
--  Promote Override to Profile (one-shot rescue)
--
--  Makes the selected spec group's stored state the profile's own: captured values
--  become the shared defaults, its unlock mode and Buff Manager forks (where
--  present) become the baseline layouts, then EVERY spec override group on the
--  profile is deleted. For profiles accidentally built entirely inside an override
--  group. Purely additive: only existing writers repaint live, and the end state is
--  indistinguishable from a profile that never had spec overrides. Conditional
--  overrides are untouched and ride the new baseline.
-------------------------------------------------------------------------------
local _promoteSelGid = nil -- list-page dropdown selection (runtime only)

local function PromoteGroupToProfile(group)
    if not group or not group.specs or #group.specs == 0 then return end
    -- Combat re-check (the typed-confirm popup can sit open while combat starts): the
    -- tail must flush secure-frame repositioning synchronously before the reload, which
    -- lockdown blocks. Nothing is written yet, so refusing here is a clean abort.
    if InCombatLockdown() then
        CludesUI:ShowConfirmPopup({
            title = L("In Combat"),
            message = L(
                "Promoting an override reloads the UI and cannot run in combat. Leave combat and try again."
            ),
            confirmText = L("OK"),
            hideCancel = true,
        })
        return
    end
    -- The reload is asked for first in the click (RequestReload); the client
    -- reloads only once this function has finished, so every step below lands.
    CludesUI.RequestReload()
    -- Bank any open session and leave the Default view so the stores hold the
    -- freshest edits and live holds canonical spec values.
    CludesUI.SpecOverrides_CloseEditSessions()

    -- 1) VALUES: the group's stored values become the recorded defaults.
    --    Resolution mirrors WriteGroupValues (first member spec's map, per-fkey
    --    fallback to the current default), so the promoted baseline is exactly
    --    what "editing as" the group shows.
    local storeTbl = GetStore()
    local seed = group.specs[1]
    if storeTbl then
        for _, item in ipairs(storeTbl) do
            local def = item.values and item.values.default
            local m = item.values and item.values[seed]
            if def and m then
                for fieldKey in pairs(def) do
                    local v = m[fieldKey]
                    -- Blacklisted paths never apply; match-owned size keys belong to
                    -- the match engine (the layer promote below carries the real
                    -- geometry). NIL_SENT markers promote as-is: the default writer
                    -- decodes them behind its own nil-poison guard.
                    if
                        v ~= nil
                        and type(v) ~= "table"
                        and not BlacklistedFKey(fieldKey)
                        and not MatchOwnedFKey(fieldKey)
                    then
                        def[fieldKey] = v
                    end
                end
            end
        end
    end
    -- Write the promoted defaults live while the entries still exist (the store
    -- is wiped below and nothing could repaint them afterwards). Writes are
    -- value-equal no-ops for specs already on the group's values.
    WriteDefaultValues()

    -- 2) UNLOCK LAYOUT: the group's fork becomes the baseline, resolved as
    --    ApplyLayer resolves a live fork: links wholesale, position stores with
    --    per-key baseline gap-fill, grow keys under the authority rule, elems
    --    overlaid onto the baseline's. All copies -- the new baseline shares no
    --    tables with the wiped fork buckets.
    local cfg = GetUnlockStore()
    if cfg then
        local layerRec = cfg.layouts and cfg.layouts[group.id]
        local base = cfg.baselineLayout
        if layerRec then
            local nb = {
                anchors = {},
                widthMatch = {},
                heightMatch = {},
                cdmGrow = {},
                abGrow = {},
                elems = {},
            }
            for key, val in pairs(layerRec.anchors or {}) do
                if not IsTBBChildKey(key) then nb.anchors[key] = DeepCopy(val) end
            end
            for key, val in pairs(layerRec.widthMatch or {}) do
                if not IsTBBChildKey(key) then nb.widthMatch[key] = val end
            end
            for key, val in pairs(layerRec.heightMatch or {}) do
                if not IsTBBChildKey(key) then nb.heightMatch[key] = val end
            end
            -- Match extras ride with the links (a fork without them promotes none).
            nb.widthMatchExtra, nb.heightMatchExtra = {}, {}
            for key, val in pairs(layerRec.widthMatchExtra or {}) do
                if not IsTBBChildKey(key) then nb.widthMatchExtra[key] = val end
            end
            for key, val in pairs(layerRec.heightMatchExtra or {}) do
                if not IsTBBChildKey(key) then nb.heightMatchExtra[key] = val end
            end
            local function MergePos(lp, bp)
                local out = lp and DeepCopy(lp) or (bp and DeepCopy(bp) or nil)
                if lp and bp then
                    for key, val in pairs(bp) do
                        if out[key] == nil then out[key] = DeepCopy(val) end
                    end
                end
                return out
            end
            nb.cdmPos = MergePos(layerRec.cdmPos, base and base.cdmPos)
            nb.abPos = MergePos(layerRec.abPos, base and base.abPos)
            -- A grow store is authoritative only when its layer was harvested
            -- with the owning module loaded (pos store present); effective =
            -- layer's grow, else the baseline's.
            local function MergeGrow(out, lAuth, lg, bAuth, bg)
                if bAuth and bg then
                    for key, val in pairs(bg) do
                        out[key] = val
                    end
                end
                if lAuth and lg then
                    for key, val in pairs(lg) do
                        out[key] = val
                    end
                end
            end
            MergeGrow(
                nb.cdmGrow,
                layerRec.cdmPos ~= nil,
                layerRec.cdmGrow,
                base and base.cdmPos ~= nil,
                base and base.cdmGrow
            )
            MergeGrow(
                nb.abGrow,
                layerRec.abPos ~= nil,
                layerRec.abGrow,
                base and base.abPos ~= nil,
                base and base.abGrow
            )
            if base and base.elems then
                for key, record in pairs(base.elems) do
                    if not LayerSkipsKey(key) then nb.elems[key] = DeepCopy(record) end
                end
            end
            for key, record in pairs(layerRec.elems or {}) do
                if not LayerSkipsKey(key) then nb.elems[key] = DeepCopy(record) end
            end
            cfg.baselineLayout = nb
        end
        wipe(cfg.layouts)
        cfg.active = nil
    end

    -- 3) BUFF MANAGER: BM layers are complete wholesale subtrees; the fork
    --    (when present) becomes the baseline verbatim.
    local bs = GetBmStore()
    if bs then
        local bl = bs.layouts and bs.layouts[group.id]
        if bl then bs.baselineLayout = DeepCopy(bl) end
        wipe(bs.layouts)
        bs.active = nil
    end

    -- 3b) DEBUFF MANAGER: same wholesale promote as the BM store.
    local ds = GetDmStore()
    if ds then
        local dl = ds.layouts and ds.layouts[group.id]
        if dl then ds.baselineLayout = DeepCopy(dl) end
        wipe(ds.layouts)
        ds.active = nil
    end

    -- 4) DELETE the spec override system: every group and entry. The promoted
    --    values are already live and the promoted layouts are the baselines,
    --    so from here the profile simply IS the override.
    local groupList = GetGroups()
    if groupList then wipe(groupList) end
    if storeTbl then wipe(storeTbl) end
    RebuildFKeyIndex()

    -- 5) CONVERGE live onto the new baselines, forced: with the groups gone the
    --    resolver wants the baseline (or a live conditional fork over it), and
    --    the same-layer early-out would skip the repaint for a spec that was
    --    NOT on the promoted fork. Where live already matches, writes are
    --    value-equal and the flush's equality guards no-op. pcall like the
    --    import converge: an error must not strand the cleanup half-done.
    local sid = CurrentSpecID()
    if sid then
        pcall(CludesUI.SpecOverrides_ApplyUnlock, sid, true)
        pcall(CludesUI.SpecOverrides_ApplyBm, sid, true)
        pcall(CludesUI.SpecOverrides_ApplyDm, sid, true)
    end
    -- 6) FLUSH before the reload asked for at the top. The converge's element
    --    writes are DEFERRED (FlushUnlock) and reloading inside that window
    --    strands them: the logout bank keeps the intent in the bucket, but the
    --    post-reload login early-outs on the nil active pointer and never
    --    paints it back into module DBs. Flush synchronously (out of combat by
    --    the gate above); the reload then rebuilds every runtime cache, ticker
    --    and session structure clean.
    pcall(CludesUI.SpecOverrides_FlushUnlock)
end

--- Page builder for the "Spec Overrides" tab (called from the Profiles &
--- Presets module registration).
function CludesUI.SpecOverrides_BuildListPage(host, startY)
    local CreateFrame = CludesUI._Pool.CreateFrame
    local W = CludesUI.Widgets
    local rowY = startY
    -- Skip during a hidden search pre-build: the page is only indexed for its
    -- static labels, and pruning mutates saved profile data -- not something a
    -- read-only indexing pass may do as a side effect.
    if not CludesUI._prebuilding then PruneOrphanEntries() end
    local storeTbl = GetStore()
    local groupList = GetGroups() or {}
    local us = GetUnlockStore()
    local layoutList
    if us then
        for _, group in ipairs(groupList) do
            if us.layouts[group.id] ~= nil then
                layoutList = layoutList or {}
                layoutList[#layoutList + 1] = group
            end
        end
    end
    local bs = GetBmStore()
    local bmList
    if bs then
        for _, group in ipairs(groupList) do
            if bs.layouts[group.id] ~= nil then
                bmList = bmList or {}
                bmList[#bmList + 1] = group
            end
        end
    end
    local dds = GetDmStore()
    local dmList
    if dds then
        for _, group in ipairs(groupList) do
            if dds.layouts[group.id] ~= nil then
                dmList = dmList or {}
                dmList[#dmList + 1] = group
            end
        end
    end

    if (not storeTbl or #storeTbl == 0) and not layoutList and not bmList and not dmList then
        local _, h = W:SectionHeader(host, L("Spec Overrides"), rowY)
        rowY = rowY - h
        local CONTENT_PAD = CludesUI.CONTENT_PAD or 40
        local hintText = CreateFrame("Frame", nil, host)
        hintText:SetSize(host:GetWidth() - CONTENT_PAD * 2, 80)
        hintText:SetPoint("TOPLEFT", host, "TOPLEFT", CONTENT_PAD, rowY)
        local fs = CludesUI.MakeFont(hintText, 13, nil, 1, 1, 1, 0.5)
        fs:SetPoint("TOPLEFT", hintText, "TOPLEFT", 20, -10)
        fs:SetWidth(hintText:GetWidth() - 40)
        fs:SetJustifyH("LEFT")
        fs:SetText(
            L(
                "No spec overrides yet. Click the spec glyph next to the module search bar, select or create a spec group, and any setting you change while editing as that group is saved here."
            )
        )
        rowY = rowY - 90
        return -rowY + 40
    end

    -- TOP section: custom unlock modes (one whole-layout fork per group).
    if layoutList then
        local _, hh = W:SectionHeader(host, "Custom Layout Modes", rowY)
        rowY = rowY - hh
        for _, group in ipairs(layoutList) do
            local _, rowH = BuildUnlockLayoutRow(host, rowY, group)
            rowY = rowY - rowH
        end
    end

    -- Custom Buff Manager forks (Raid Frames Buff Manager tab).
    if bmList then
        local _, hh = W:SectionHeader(host, "Custom Buff Managers", rowY)
        rowY = rowY - hh
        for _, group in ipairs(bmList) do
            local _, rowH = BuildUnlockLayoutRow(host, rowY, group, BM_ROW_SPEC)
            rowY = rowY - rowH
        end
    end

    -- Custom Debuff Manager forks (Raid Frames Debuff Manager tab).
    if dmList then
        local _, hh = W:SectionHeader(host, "Custom Debuff Managers", rowY)
        rowY = rowY - hh
        for _, group in ipairs(dmList) do
            local _, rowH = BuildUnlockLayoutRow(host, rowY, group, DM_ROW_SPEC)
            rowY = rowY - rowH
        end
    end

    -- Bucket entries under EVERY group that customizes them: a slot is ONE
    -- shared entry across groups (a second group's edits bank into the first
    -- group's entry), so an entry lists under its creating group AND under any
    -- group whose member specs store a value differing from the entry's shared
    -- default. Derived live -- no stored ownership metadata.
    local function GroupCustomizes(item, group)
        if item.group == group.id then return true end
        local def = item.values and item.values.default
        if not def then return false end
        for _, sid in ipairs(group.specs or {}) do
            local m = item.values[sid]
            if m then
                for fieldKey, dv in pairs(def) do
                    if m[fieldKey] ~= nil and m[fieldKey] ~= dv then return true end
                end
            end
        end
        return false
    end
    local byGroup, ungrouped = {}, {}
    for _, item in ipairs(storeTbl or {}) do
        local listed = false
        for _, group in ipairs(groupList) do
            if GroupCustomizes(item, group) then
                byGroup[group.id] = byGroup[group.id] or {}
                table.insert(byGroup[group.id], item)
                listed = true
            end
        end
        if not listed then ungrouped[#ungrouped + 1] = item end
    end

    for _, group in ipairs(groupList) do
        local list = byGroup[group.id]
        if list and #list > 0 then
            local _, hh = W:SectionHeader(host, group.name or "?", rowY)
            rowY = rowY - hh
            for _, item in ipairs(list) do
                local _, rowH = BuildListRow(host, rowY, item)
                rowY = rowY - rowH
            end
        end
    end
    if #ungrouped > 0 then
        local _, hh = W:SectionHeader(host, "Ungrouped", rowY)
        rowY = rowY - hh
        for _, item in ipairs(ungrouped) do
            local _, rowH = BuildListRow(host, rowY, item)
            rowY = rowY - rowH
        end
    end

    -- STRANDED values: per-spec overrides no editing session can reach (see
    -- SpecStrandedOnEntry). They apply at every boundary but are invisible in
    -- the group buckets above, so each gets a row with a per-value Remove.
    local stranded
    for _, item in ipairs(storeTbl or {}) do
        if item.values then
            for key in pairs(item.values) do
                if type(key) == "number" and SpecStrandedOnEntry(item, key) then
                    stranded = stranded or {}
                    stranded[#stranded + 1] = { entry = item, spec = key }
                end
            end
        end
    end
    if stranded then
        table.sort(stranded, function(a, button) return a.spec < button.spec end)
        local _, hh = W:SectionHeader(host, "Stranded Overrides", rowY)
        rowY = rowY - hh
        local CONTENT_PAD = CludesUI.CONTENT_PAD or 40
        local hintText = CludesUI.MakeFont(host, 11, nil, 1, 1, 1, 0.45)
        hintText:SetPoint("TOPLEFT", host, "TOPLEFT", CONTENT_PAD + 20, rowY)
        hintText:SetWidth(host:GetWidth() - CONTENT_PAD * 2 - 40)
        hintText:SetJustifyH("LEFT")
        hintText:SetText(
            L(
                "These specs hold override values that no group's editing mode can reach anymore (left behind by membership changes). They still apply. Remove one to return that spec to the shared default."
            )
        )
        rowY = rowY - 34
        for _, s in ipairs(stranded) do
            local _, rowH = BuildStrandedRow(host, rowY, s.entry, s.spec)
            rowY = rowY - rowH
        end
    end

    -- DANGER ZONE: one-shot "this override IS my profile" rescue. Rendered only
    -- while a group exists to promote.
    if #groupList > 0 then
        rowY = rowY - 14
        local _, hh = W:SectionHeader(host, "Promote Override to Profile", rowY)
        rowY = rowY - hh
        local CONTENT_PAD = CludesUI.CONTENT_PAD or 40
        local hintText = CludesUI.MakeFont(host, 11, nil, 1, 1, 1, 0.45)
        hintText:SetPoint("TOPLEFT", host, "TOPLEFT", CONTENT_PAD + 20, rowY)
        hintText:SetWidth(host:GetWidth() - CONTENT_PAD * 2 - 40)
        hintText:SetJustifyH("LEFT")
        hintText:SetText(
            L(
                "Rescue tool for a profile built inside an override: the selected group's settings and layouts become this profile's own baseline, then ALL spec override groups are deleted. Conditional overrides are not affected."
            )
        )
        rowY = rowY - 44
        local ddValues, ddOrder = {}, {}
        for _, gg in ipairs(groupList) do
            ddValues[gg.id] = gg.name or ("Group " .. gg.id)
            ddOrder[#ddOrder + 1] = gg.id
        end
        if not _promoteSelGid or not GroupById(_promoteSelGid) then _promoteSelGid = groupList[1].id end
        local _, dh = W:WideDropdown(
            host,
            "Override to Promote",
            rowY,
            ddValues,
            function() return _promoteSelGid end,
            function(v) _promoteSelGid = v end,
            ddOrder,
            300
        )
        rowY = rowY - dh
        rowY = rowY - 6
        local BTN_W, BTN_H = 300, 38
        local lerp = CludesUI.lerp
        local DARK_BG = CludesUI.DARK_BG
        local btn = CreateFrame("Button", nil, host)
        btn:SetSize(BTN_W, BTN_H)
        btn:SetPoint("TOP", host, "TOP", 0, rowY)
        btn:SetFrameLevel(host:GetFrameLevel() + 5)
        btn:SetAlpha(0.85)
        local bg = CludesUI.SolidTex(btn, "BACKGROUND", DARK_BG.r, DARK_BG.g, DARK_BG.b, 0.92)
        bg:SetAllPoints()
        local brd = CludesUI.MakeRoundedBorder(btn, 0.8, 0.2, 0.2, 0.5, bg)
        local caption = CludesUI.MakeFont(btn, 13, nil, 0.9, 0.3, 0.3)
        caption:SetAlpha(0.7)
        caption:SetPoint("CENTER")
        caption:SetText(L("Promote Override & Delete ALL Overrides"))
        do
            local FADE_DUR = 0.1
            local progress, target = 0, 0
            local function Apply(t)
                caption:SetTextColor(lerp(0.9, 1, t), lerp(0.3, 0.35, t), lerp(0.3, 0.35, t), lerp(0.7, 1, t))
                brd:SetColor(0.8, 0.2, 0.2, lerp(0.5, 0.8, t))
            end
            local function OnUpdate(self, elapsed)
                local dir = (target == 1) and 1 or -1
                progress = progress + dir * (elapsed / FADE_DUR)
                if (dir == 1 and progress >= 1) or (dir == -1 and progress <= 0) then
                    progress = target
                    self:SetScript("OnUpdate", nil)
                end
                Apply(progress)
            end
            btn:SetScript("OnEnter", function(self)
                target = 1
                self:SetScript("OnUpdate", OnUpdate)
            end)
            btn:SetScript("OnLeave", function(self)
                target = 0
                self:SetScript("OnUpdate", OnUpdate)
            end)
        end
        btn:SetScript("OnClick", function()
            local pg = GroupById(_promoteSelGid)
            if not pg then return end
            -- The promote ends in a synchronous flush + ReloadUI, neither
            -- of which belongs in combat lockdown.
            if InCombatLockdown() then
                CludesUI:ShowConfirmPopup({
                    title = L("In Combat"),
                    message = L(
                        "Promoting an override reloads the UI and cannot run in combat. Leave combat and try again."
                    ),
                    confirmText = L("OK"),
                    hideCancel = true,
                })
                return
            end
            -- Modules with captured overrides must be loaded: promoted
            -- values for an unloaded module cannot be written live, and the
            -- store they lived in is deleted at the end -- silent loss.
            local missingSet, missingList
            for _, item in ipairs(GetStore() or {}) do
                for fieldKey in pairs(item.values and item.values.default or {}) do
                    if not BlacklistedFKey(fieldKey) and not FKeyLoaded(fieldKey) then
                        local folder = SplitFKey(fieldKey)
                        if folder and not (missingSet and missingSet[folder]) then
                            missingSet = missingSet or {}
                            missingSet[folder] = true
                            missingList = missingList or {}
                            missingList[#missingList + 1] = folder:gsub("^CludesUI", "")
                        end
                    end
                end
            end
            if missingList then
                CludesUI:ShowConfirmPopup({
                    title = L("Enable Modules First"),
                    message = string.format(
                        L(
                            "Captured overrides reference disabled modules (%s). Enable them and reload before promoting, or those settings would be lost."
                        ),
                        table.concat(missingList, ", ")
                    ),
                    confirmText = L("OK"),
                    hideCancel = true,
                })
                return
            end
            CludesUI:ShowConfirmPopup({
                title = L("Promote Override to Profile"),
                message = string.format(
                    L(
                        "This permanently overwrites this profile's settings with the override '%s': its captured settings and its custom Layout Mode and Buff Manager layouts (where present) become the profile's own baseline for every spec. ALL spec override groups on this profile are then deleted and the UI reloads. Conditional overrides are not affected."
                    ),
                    pg.name or "?"
                ),
                disclaimer = L("This cannot be undone. Consider exporting this profile as a backup first."),
                typeToConfirm = "Confirm",
                confirmText = L("Promote & Reload"),
                cancelText = L("Cancel"),
                onConfirm = function() PromoteGroupToProfile(pg) end,
            })
        end)
        rowY = rowY - BTN_H - 10
    end

    return -rowY + 40
end

--- Page builder for the "Conditional Overrides" tab (mirror of the spec tab).
function CludesUI.Conditions_BuildListPage(host, startY)
    local CreateFrame = CludesUI._Pool.CreateFrame
    local W = CludesUI.Widgets
    local rowY = startY
    Cond.PruneEntries()
    local storeTbl = Cond.GetStore()
    local groupList = CludesUI.Conditions_GetGroups() or {}
    local cs = Cond.GetUnlockStore()

    local layoutList
    if cs then
        for _, group in ipairs(groupList) do
            if cs.layouts[group.id] ~= nil then
                layoutList = layoutList or {}
                layoutList[#layoutList + 1] = group
            end
        end
    end
    local cbs = GetCondBmStore()
    local bmList
    if cbs then
        for _, group in ipairs(groupList) do
            if cbs.layouts[group.id] ~= nil then
                bmList = bmList or {}
                bmList[#bmList + 1] = group
            end
        end
    end
    local cds = GetCondDmStore()
    local dmList
    if cds then
        for _, group in ipairs(groupList) do
            if cds.layouts[group.id] ~= nil then
                dmList = dmList or {}
                dmList[#dmList + 1] = group
            end
        end
    end

    if
        (not storeTbl or #storeTbl == 0)
        and not layoutList
        and not bmList
        and not dmList
        and #groupList == 0
    then
        local _, h = W:SectionHeader(host, L("Conditional Overrides"), rowY)
        rowY = rowY - h
        local CONTENT_PAD = CludesUI.CONTENT_PAD or 40
        local hintText = CreateFrame("Frame", nil, host)
        hintText:SetSize(host:GetWidth() - CONTENT_PAD * 2, 80)
        hintText:SetPoint("TOPLEFT", host, "TOPLEFT", CONTENT_PAD, rowY)
        local fs = CludesUI.MakeFont(hintText, 13, nil, 1, 1, 1, 0.5)
        fs:SetPoint("TOPLEFT", hintText, "TOPLEFT", 20, -10)
        fs:SetWidth(hintText:GetWidth() - 40)
        fs:SetJustifyH("LEFT")
        fs:SetText(
            L(
                "No conditional overrides yet. Click the Conditional Overrides button next to the module search bar and create a conditional group (Dungeon, Raid, Keybind...). Spec overrides always take precedence over conditionals."
            )
        )
        rowY = rowY - 90
        return -rowY + 40
    end

    -- TOP section: custom unlock modes (one whole-layout fork per group).
    if layoutList then
        local _, hh = W:SectionHeader(host, "Custom Layout Modes", rowY)
        rowY = rowY - hh
        for _, group in ipairs(layoutList) do
            local CONTENT_PAD = CludesUI.CONTENT_PAD or 40
            local line = CreateFrame("Frame", nil, host)
            line:SetSize(host:GetWidth() - CONTENT_PAD * 2, 36)
            line:SetPoint("TOPLEFT", host, "TOPLEFT", CONTENT_PAD, rowY)
            local label = CludesUI.MakeFont(line, 13, nil, 1, 1, 1, 0.9)
            label:SetPoint("LEFT", line, "LEFT", 20, 0)
            label:SetText(group.name or "?")
            local trail = CludesUI.MakeFont(line, 11, nil, GOLD_R, GOLD_G, GOLD_B, 0.75)
            trail:SetPoint("LEFT", label, "RIGHT", 10, 0)
            trail:SetText(L("Custom Layout Mode"))
            local button = CreateFrame("Button", nil, line)
            button:SetSize(116, 22)
            button:SetPoint("RIGHT", line, "RIGHT", -20, 0)
            CludesUI.SolidTex(button, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
            local brd = CludesUI.MakeRoundedBorder(button, 1, 1, 1, 0.22)
            local caption = CludesUI.MakeFont(button, 11, nil, 1, 1, 1, 0.8)
            caption:SetPoint("CENTER")
            caption:SetText(L("Delete"))
            button:SetScript("OnEnter", function()
                if brd and brd.SetColor then brd:SetColor(1, 0.35, 0.35, 0.8) end
            end)
            button:SetScript("OnLeave", function()
                if brd and brd.SetColor then brd:SetColor(1, 1, 1, 0.22) end
            end)
            local gid = group.id
            local gname = group.name or "?"
            button:SetScript("OnClick", function()
                CludesUI:ShowConfirmPopup({
                    title = L("Delete Custom Layout Mode"),
                    message = string.format(
                        L(
                            "Delete the custom layout mode for '%s'? Its conditions return to your default layout mode layout."
                        ),
                        gname
                    ),
                    confirmText = L("Delete"),
                    cancelText = L("Cancel"),
                    onConfirm = function()
                        CludesUI.Conditions_RemoveUnlockLayout(gid)
                        CludesUI:RefreshPage(true)
                    end,
                })
            end)
            rowY = rowY - 38
        end
    end

    -- Custom Buff Manager forks (Raid Frames Buff Manager tab).
    if bmList then
        local _, hh = W:SectionHeader(host, "Custom Buff Managers", rowY)
        rowY = rowY - hh
        for _, group in ipairs(bmList) do
            local _, rowH = BuildUnlockLayoutRow(host, rowY, group, BM_ROW_COND)
            rowY = rowY - rowH
        end
    end

    -- Custom Debuff Manager forks (Raid Frames Debuff Manager tab).
    if dmList then
        local _, hh = W:SectionHeader(host, "Custom Debuff Managers", rowY)
        rowY = rowY - hh
        for _, group in ipairs(dmList) do
            local _, rowH = BuildUnlockLayoutRow(host, rowY, group, DM_ROW_COND)
            rowY = rowY - rowH
        end
    end

    -- Captured value entries bucketed under EVERY conditional group that
    -- customizes them (creator, plus any group whose stored map differs from
    -- the entry's shared default -- same shared-slot rule as the spec list).
    for _, group in ipairs(groupList) do
        local list = {}
        for _, item in ipairs(storeTbl or {}) do
            local owns = item.group == group.id
            if not owns and item.values and item.values.default then
                local m = item.values[group.id]
                if m then
                    for fieldKey, dv in pairs(item.values.default) do
                        if m[fieldKey] ~= nil and m[fieldKey] ~= dv then
                            owns = true
                            break
                        end
                    end
                end
            end
            if owns then list[#list + 1] = item end
        end
        if #list > 0 then
            local _, hh = W:SectionHeader(host, group.name or "?", rowY)
            rowY = rowY - hh
            for _, item in ipairs(list) do
                local _, rowH = BuildListRow(host, rowY, item)
                rowY = rowY - rowH
            end
        end
    end

    return -rowY + 40
end

Inner.PruneOrphanEntries = PruneOrphanEntries
Inner.broken = false
