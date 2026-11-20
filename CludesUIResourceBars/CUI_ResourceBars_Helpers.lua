if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_ResourceBars_Options.lua
--  Registers the Resource Bars module with CludesUI
--  Pages: Class, Power and Health Bars | Cast Bar | Unlock Mode
-------------------------------------------------------------------------------
local ADDON_NAME, mod = ...
-- The options page pool's table (CludesUI_PixelPerfect.lua makes it; the
-- options addon fills it in place), read through this local and never through
-- the public slot.
local POOL = CludesUI._Pool

local function DB()
    local saved = _G._CURB_AceDB
    return saved and saved.profile
end

-- A threshold card is shadowed when an earlier card with the same talent gate covers an
-- overlapping spec scope - a duplicate the resolver can never reach (first match wins).
-- Cards that target another spec, or a talent you aren't running right now, are not
-- shadowed. Spec-overlap mirrors the popup's SpecsConflict (a concrete spec shared, or
-- both "All Specs"); an All-Specs card and a spec-specific card do not shadow each
-- other since the resolver prioritises the specific one.
mod._CURB_IsThresholdCardShadowed = function(entries, position)
    local current = entries and entries[position]
    if not current or not current.specIDs then
        return false
    end
    -- WoW Forever: the class resolves as one spec (ns.ForeverThresholdPick; nil
    -- = All Specs only), so a live card naming specs of the player's class, none
    -- of them that one, never applies on this character.
    if CludesUI.IS_FOREVER then
        local pick = mod.ForeverThresholdPick(entries)
        if not mod.ThresholdCardLiveFor(current, pick) then
            for _, spec in ipairs(current.specIDs) do
                if CludesUI.IsPlayerSpec(spec) and mod.ThresholdCardLiveFor(current, spec) then
                    return true
                end
            end
        end
    end
    local curGate = current.talentSpellID
    local curAll, curSet = false, {}
    for _, spec in ipairs(current.specIDs) do
        if spec == 0 then
            curAll = true
        else
            curSet[spec] = true
        end
    end
    for jdx = 1, position - 1 do
        local o = entries[jdx]
        if o and o.specIDs and o.talentSpellID == curGate then
            for _, spec in ipairs(o.specIDs) do
                if spec == 0 then
                    if curAll then
                        return true
                    end
                elseif curSet[spec] then
                    return true
                end
            end
        end
    end
    return false
end

-- The unlock-mode open/close cycle leaves these overlays with an undefined rect, so the
-- frame and its regions draw nothing even though it still exists. Capture the overlay's
-- own anchors + height at build time, then on show re-assert them one frame later
mod.ERB_OverlayHealOnShow = function(shade, obg, olbl, bgAlpha)
    local txt = olbl:GetText() or ""
    local pts = {}
    for p = 1, shade:GetNumPoints() do
        pts[p] = { shade:GetPoint(p) }
    end
    local ovH = shade:GetHeight()
    shade:SetScript("OnShow", function()
        -- An overlay of the options page pool dressed again before the next
        -- frame belongs to another build by then: the heal leaves it alone.
        local gen = POOL.Gen and POOL.Gen(shade)
        C_Timer.After(0, function()
            if POOL.Gen and POOL.Gen(shade) ~= gen then
                return
            end
            if not shade:IsVisible() then
                return
            end
            if #pts > 0 then
                shade:ClearAllPoints()
                for p = 1, #pts do
                    shade:SetPoint(unpack(pts[p]))
                end
            end
            if ovH and ovH > 0 then
                shade:SetHeight(ovH)
            end
            obg:SetColorTexture(13 / 255, 17 / 255, 25 / 255, bgAlpha or 0.96)
            obg:ClearAllPoints()
            obg:SetAllPoints(shade)
            olbl:ClearAllPoints()
            olbl:SetPoint("CENTER")
            olbl:SetText("")
            olbl:SetText(txt)
        end)
    end)
end

-- Simple page: when the player's current spec overrides this section in
-- Advanced, its Simple controls are being ignored right now. Cover them with
-- a click-to-Advanced hint so edits here aren't silently lost
-- sectionKey: "health" | "primary" | "secondary".
mod.ERB_SimpleOverrideOverlay = function(hostFrame, topY, botY, sectionKey)
    if not topY then
        return
    end
    if not (_G._CURB_CurSpecOverridesSection and _G._CURB_CurSpecOverridesSection(sectionKey)) then
        return
    end
    local EGc = CludesUI.CLUDES_GREEN or { r = 0.30, g = 0.79, b = 0.94 }
    local CPAD = CludesUI.CONTENT_PAD or 45
    local Pix = CludesUI.PanelPP or CludesUI.PP
    -- On an options page (an options page pool host) the overlay is pooled
    -- with the page.
    local shade = POOL.CreateFrame("Button", nil, hostFrame)
    -- Anchor via PP so it lines up with the section header/rows.
    Pix.Point(shade, "TOPLEFT", hostFrame, "TOPLEFT", CPAD, topY)
    Pix.Point(shade, "TOPRIGHT", hostFrame, "TOPRIGHT", -CPAD, topY)
    Pix.Point(shade, "BOTTOMLEFT", hostFrame, "TOPLEFT", CPAD, botY)
    shade:SetFrameLevel(hostFrame:GetFrameLevel() + 50)
    local obg = shade:CreateTexture(nil, "BACKGROUND")
    obg:SetAllPoints()
    obg:SetColorTexture(13 / 255, 17 / 255, 25 / 255, 0.9)
    local olbl = CludesUI.MakeFont(shade, 12, nil, 1, 1, 1)
    olbl:SetPoint("CENTER")
    olbl:SetTextColor(1, 1, 1, 0.7)
    olbl:SetText(
        CludesUI.L("Active spec uses Advanced settings")
            .. "   \226\128\148   "
            .. CludesUI.L("click to edit")
    )
    mod.ERB_OverlayHealOnShow(shade, obg, olbl, 0.9)
    shade:SetScript("OnEnter", function()
        olbl:SetTextColor(EGc.r, EGc.g, EGc.b, 1)
    end)
    shade:SetScript("OnLeave", function()
        olbl:SetTextColor(1, 1, 1, 0.7)
    end)
    shade:SetScript("OnClick", function()
        local profile = DB()
        if not profile then
            return
        end
        local position = GetSpecialization and GetSpecialization()
        local current = position
            and C_SpecializationInfo
            and C_SpecializationInfo.GetSpecializationInfo(position)
        if current then
            profile.advancedSelectedSpec = current
        end
        profile.barDisplayMode = "advanced"
        CludesUI:RefreshPage(true)
        -- Clicking to edit navigates to the top of the Advanced page
        CludesUI:ScrollToTop()
    end)
end

local barTypeSpecs = _G._CURB_BAR_TYPE_SPECS or {}
-- bar-type spec lookup
mod.IsSpecBarType = function(specID)
    if specID == 0 then
        return mod.IsBarTypeSecondary()
    end
    return barTypeSpecs[specID] or false
end
mod.IsEntryBarType = function(record)
    if not record or not record.specIDs or #record.specIDs == 0 then
        return false
    end
    return mod.IsSpecBarType(record.specIDs[1])
end
local SpecName = function(specID)
    if specID == 0 then
        return "All Specs"
    end
    -- WoW Forever: the spec and class names from the shared spec table, in the
    -- same "<Spec> <Class>" shape as below.
    if CludesUI.IS_FOREVER then
        local token = CludesUI.SpecClassOf(specID)
        if token then
            local sn, cn = CludesUI.RetailSpecName(specID), CludesUI.ForeverClassName(token)
            return sn and (sn .. " " .. cn) or cn
        end
    end
    -- The by-id lookup has no namespaced form and is absent on WoW Forever.
    local _, name, className
    if GetSpecializationInfoByID then
        _, name, _, _, _, _, className = GetSpecializationInfoByID(specID)
    end
    if name and className then
        return name .. " " .. className
    end
    return name or ("Spec " .. specID)
end
mod.EntryLabel = function(record)
    if not record or not record.specIDs or #record.specIDs == 0 then
        return "Unknown"
    end
    if record.specIDs[1] == 0 then
        return "All Specs"
    end
    local nameList = {}
    -- WoW Forever: a class the card holds whole reads as the class; a partial
    -- class lists its specs, so cards for different specs stay distinct.
    if CludesUI.IS_FOREVER then
        local held, done = {}, {}
        for _, spellRef in ipairs(record.specIDs) do
            held[spellRef] = true
        end
        for _, spellRef in ipairs(record.specIDs) do
            local token = CludesUI.SpecClassOf(spellRef)
            local classIDs = CludesUI.ForeverClassSpecIDs(token)
            if not classIDs then
                nameList[#nameList + 1] = SpecName(spellRef)
            elseif not done[token] then
                done[token] = true
                local whole = true
                for i = 1, #classIDs do
                    if not held[classIDs[i]] then
                        whole = false
                        break
                    end
                end
                if whole then
                    nameList[#nameList + 1] = CludesUI.ForeverClassName(token)
                else
                    for i = 1, #classIDs do
                        if held[classIDs[i]] then
                            nameList[#nameList + 1] = SpecName(classIDs[i])
                        end
                    end
                end
            end
        end
        return table.concat(nameList, ", ")
    end
    for _, spellRef in ipairs(record.specIDs) do
        nameList[#nameList + 1] = SpecName(spellRef)
    end
    return table.concat(nameList, ", ")
end

-- Helper: returns true if the current class/spec uses a bar-type secondary (no pips)
mod.IsBarTypeSecondary = function()
    local _, castFrame = UnitClass("player")
    local specInfo = C_SpecializationInfo.GetSpecialization()
    local gsr = _G._CURB_GetSecondaryResource
    local details = gsr and gsr()
    if details and details.power == "IRONFUR_BAR" then
        return true
    end -- Guardian Ironfur bar
    if details and details.power == "IGNOREPAIN_BAR" then
        return true
    end -- Prot Warrior Ignore Pain bar
    -- WoW Forever: no bar-type class resource exists there (the runtime never
    -- builds one), so the retail spec positions below do not apply.
    if CludesUI.IS_FOREVER then
        return false
    end
    if castFrame == "DRUID" and specInfo == 1 then
        return true
    end -- Balance (Astral Power bar)
    if castFrame == "SHAMAN" and specInfo == 1 then
        return true
    end -- Elemental
    if castFrame == "PRIEST" and specInfo == 3 then
        return true
    end -- Shadow
    if castFrame == "MONK" and specInfo == 1 then
        return true
    end -- Brewmaster
    if castFrame == "HUNTER" and (specInfo == 1 or specInfo == 2) then
        return true
    end -- BM / MM Focus bar
    if castFrame == "DEMONHUNTER" and specInfo then
        local specID = C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo(specInfo)
        if specID == 1480 then
            return true
        end -- Devourer
    end
    return false
end

-- Two cards collide in the resolver only if they share a spec context: a common
-- non-zero specID, OR both are All Specs (0). (A spec-specific card and an All-Specs
-- card sit in different resolver tiers, so they never collide.)
mod.SpecsConflict = function(aIDs, bIDs)
    if not aIDs or not bIDs then
        return false
    end
    local aHasAll, aSet = false, {}
    for _, s in ipairs(aIDs) do
        if s == 0 then
            aHasAll = true
        else
            aSet[s] = true
        end
    end
    for _, s in ipairs(bIDs) do
        if s == 0 then
            if aHasAll then
                return true
            end
        elseif aSet[s] then
            return true
        end
    end
    return false
end

-- An entry counts as configured when its single threshold is on (a missing flag
-- means on, for migrated entries), it has hash lines, or when multi-band coloring
-- replaces it. The band fallbacks mirror ResolveThresholdSpecEntry's
-- ResolveBandConfig: both the enable flag and the band list fall back to the bar table.
local function ThresholdEntryConfigured(edge, record)
    if record.thresholdEnabled ~= false then
        return true
    end
    if record.hashValues and record.hashValues ~= "" then
        return true
    end
    local multi = record.multiBandEnabled
    if multi == nil then
        multi = edge.multiBandEnabled
    end
    if not multi then
        return false
    end
    local bands = (record.bands and #record.bands > 0) and record.bands or edge.bands
    return (bands and #bands > 0) and true or false
end

-- Threshold notice: the spec names holding a configured threshold on a bar table,
-- for the info badge on the Threshold & Hash Lines button. Entries with no specIDs
-- (legacy druid form-mode lists) name no spec. Returns nil when nothing is
-- configured, else the comma-joined name list plus whether one of those entries
-- applies to the spec being played.
mod.ThresholdNoticeInfo = function(edge)
    local entries = edge and edge.thresholdSpecs
    if not entries or #entries == 0 then
        return nil
    end
    local activeSpecID = _G._CURB_ResolveSpecIDCached and _G._CURB_ResolveSpecIDCached()
    -- WoW Forever: the spec the thresholds resolve as (ns.ForeverThresholdPick; nil = All Specs only).
    if CludesUI.IS_FOREVER then
        activeSpecID = mod.ForeverThresholdPick(entries)
    end
    local nameList, seen, isActive = {}, {}, false
    for _, record in ipairs(entries) do
        if ThresholdEntryConfigured(edge, record) then
            local labelText, hitsActive
            if record.specIDs and #record.specIDs > 0 then
                labelText = mod.EntryLabel(record)
                for _, spellRef in ipairs(record.specIDs) do
                    if spellRef == 0 or spellRef == activeSpecID then
                        hitsActive = true
                        break
                    end
                end
            end
            if labelText and not seen[labelText] then
                seen[labelText] = true
                nameList[#nameList + 1] = labelText
            end
            if hitsActive then
                isActive = true
            end
        end
    end
    if #nameList == 0 then
        return nil
    end
    return table.concat(nameList, ", "), isActive
end

-- Enumerate every choosable talent in the active loadout (class + spec trees),
-- returning a name-sorted list of { spellID, name }. Returns {} when traits
-- aren't available yet. Only the active loadout is enumerable by the API.
mod.GetLoadoutTalents = function()
    local talents = {}
    local configID = C_ClassTalents
        and C_ClassTalents.GetActiveConfigID
        and C_ClassTalents.GetActiveConfigID()
    if not configID then
        return talents
    end
    local configInfo = C_Traits and C_Traits.GetConfigInfo and C_Traits.GetConfigInfo(configID)
    if not configInfo or not configInfo.treeIDs then
        return talents
    end

    local seenSpells = {}
    for _, treeID in ipairs(configInfo.treeIDs) do
        local nodes = C_Traits.GetTreeNodes(treeID)
        if nodes then
            for _, nodeID in ipairs(nodes) do
                local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
                if
                    nodeInfo
                    and nodeInfo.ID
                    and nodeInfo.ID > 0
                    and nodeInfo.entryIDs
                    and #nodeInfo.entryIDs > 0
                    and not nodeInfo.subTreeID
                then
                    for _, entryID in ipairs(nodeInfo.entryIDs) do
                        local entryInfo = C_Traits.GetEntryInfo(configID, entryID)
                        if entryInfo and entryInfo.definitionID then
                            local defInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
                            if defInfo and defInfo.spellID and not seenSpells[defInfo.spellID] then
                                local spellName = C_Spell.GetSpellName(defInfo.spellID)
                                if spellName and spellName ~= "" then
                                    seenSpells[defInfo.spellID] = true
                                    talents[#talents + 1] = { spellID = defInfo.spellID, name = spellName }
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(talents, function(lhs, rhs)
        return lhs.name < rhs.name
    end)
    return talents
end
