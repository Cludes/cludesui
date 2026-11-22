if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_PlayerAuraBars_Groups.lua
--
--  Debuff match mode, the candidate filters, the group layout and
--  ApplyGroupConfig.
--  Reads the earlier Player Aura Bars files through ns and ns._pabInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._pabInternals
-- CludesUIUnitFrames_PlayerAuraBars.lua or an earlier Player Aura Bars
-- file failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local BuildChain, ClassByKey, ClassEnabled = Inner.BuildChain, Inner.ClassByKey, Inner.ClassEnabled
local DEBUFF_FILTER_ORDER, DebuffSubtractFn = Inner.DEBUFF_FILTER_ORDER, Inner.DebuffSubtractFn
local MergeTypes, PAB_ApplyDmFx = Inner.MergeTypes, Inner.PAB_ApplyDmFx
local PAB_FxEntryActive, PAB_FxSafeToForce = Inner.PAB_FxEntryActive, Inner.PAB_FxSafeToForce
local PAB_FxSizeFor, PAB_FxWantsCategory = Inner.PAB_FxSizeFor, Inner.PAB_FxWantsCategory
local PabShapedSize, PabSnap = Inner.PabShapedSize, Inner.PabSnap
local VisibleCandidateClasses = Inner.VisibleCandidateClasses
local VisibleTokenClasses, DebuffCatchAllOn = Inner.VisibleTokenClasses, Inner.DebuffCatchAllOn
local ResolveSortDirection, ResolveSortMethod = Inner.ResolveSortDirection, Inner.ResolveSortMethod

local AK -- CludesUI.AuraKit, resolved at first use (see SetAK)
Inner.AKSetters[#Inner.AKSetters + 1] = function(v) AK = v end

-------------------------------------------------------------------------------
--  Debuff Match Mode (cfg.debuffMatch: nil = Match Any, "all" = Match All)
--
--  Match Any is the BuildChain union, untouched. Match All ANDs every Show pick into
--  ONE group: HARMFUL + every shown token + every shown candidate field, with the
--  Hide lane as a plain veto (!TOKEN, the opposite boolean, excludeDispelTypes), so
--  a debuff renders at most once. The dispel types stay one OR'd axis (a debuff has
--  one type: Magic + Curse = either; Dispels beside a type adds nothing). Runs only
--  with All Debuffs off and at least two Show picks; anything less builds today's
--  chain. Only rows the Filters dropdown lists take part, so a retired row's stale
--  key cannot silently empty the bar.
--
--  Icon Effects only PAINT here (they never add content, and Hide beats them): a
--  block naming a category every member already belongs to paints the whole group;
--  a block naming another category X splits it into (group AND X, painted) and
--  (group AND NOT X) -- exact, never duplicating (every category has an exact
--  complement: the negated token, the opposite boolean, or the remaining dispel
--  types; Boss, Role and Can Apply split like Important). Buttons stamp the
--  group's category LIST (link.cats) and the key names that list, since a
--  button's category is stamped once at creation. Settings-apply time only.
-------------------------------------------------------------------------------
local DebuffChainFor
do
    local LISTED = {}
    for index = 1, #DEBUFF_FILTER_ORDER do
        LISTED[DEBUFF_FILTER_ORDER[index]] = true
    end

    -- Types of `a` also in / not in `b`, as a fresh set; nil when none are left.
    local function TypesAnd(a, b)
        local result
        for key in pairs(a) do
            if b[key] then
                result = result or {}
                result[key] = true
            end
        end
        return result
    end
    local function TypesWithout(a, b)
        local result
        for key in pairs(a) do
            if not (b and b[key]) then
                result = result or {}
                result[key] = true
            end
        end
        return result
    end

    local function CopyPart(p)
        local t, c = {}, {}
        for index = 1, #p.tokens do
            t[index] = p.tokens[index]
        end
        for key, val in pairs(p.cand) do
            c[key] = val
        end
        return { tokens = t, cand = c }
    end

    local function HasToken(p, tok)
        for index = 1, #p.tokens do
            if p.tokens[index] == tok then return true end
        end
        return false
    end

    -- The group. nil = Match All does not apply; false = the picks can never match
    -- together (Non-Player with Cast By You, Cast By You with From Any Player hidden,
    -- a dispel type with Dispels hidden); else the part and the categories every
    -- member belongs to.
    local function MatchBase(conf)
        if conf.debuffMatch ~= "all" or conf.showAllDebuffs ~= false then return nil end
        local tokenClasses, candidateClasses = VisibleTokenClasses(), VisibleCandidateClasses()
        if not (tokenClasses and candidateClasses) then return nil end
        local neg = conf.negClassFilters
        local tokens, cand, cats = { "HARMFUL" }, {}, {}
        local picks, nTypes, clash = 0, 0, false
        local inc, anyType, exc, typeKey, playerTok, hideBool, dispTok
        for index = 1, #tokenClasses do
            local class = tokenClasses[index]
            if LISTED[class.key] then
                if ClassEnabled(class, false, conf) then
                    picks = picks + 1
                    tokens[#tokens + 1] = class.token
                    cats[#cats + 1] = class.key
                    if class.key == "castbyme" then playerTok = true end
                    if class.key == "dispellable" then dispTok = true end
                elseif neg and neg[class.skey] == true then
                    tokens[#tokens + 1] = class.neg or ("!" .. class.token)
                end
            end
        end
        for index = 1, #candidateClasses do
            local class = candidateClasses[index]
            local cc = class.cand
            if cc and LISTED[class.key] then
                if ClassEnabled(class, false, conf) then
                    picks = picks + 1
                    if class.key == "dispeltyped" then
                        anyType = cc.includeDispelTypes
                        cats[#cats + 1] = class.key
                    elseif cc.includeDispelTypes then
                        inc = MergeTypes(inc, cc.includeDispelTypes)
                        nTypes, typeKey = nTypes + 1, class.key
                    else
                        for key, val in pairs(cc) do
                            -- Two picks on one field (stale data only: the setters keep
                            -- Non-Player and From Any Player exclusive) never match.
                            if cand[key] ~= nil and cand[key] ~= val then clash = true end
                            cand[key] = val
                        end
                        cats[#cats + 1] = class.key
                    end
                elseif neg and neg[class.skey] == true then
                    if cc.includeDispelTypes then
                        exc = MergeTypes(exc, cc.includeDispelTypes)
                    else
                        hideBool = hideBool or {}
                        for key, val in pairs(cc) do
                            if type(val) == "boolean" then hideBool[key] = not val end
                        end
                    end
                end
            end
        end
        if picks < 2 then return nil end
        -- A Show pick owns its field; the Hide lane vetoes only what is left open.
        if hideBool then
            for key, val in pairs(hideBool) do
                if cand[key] == nil then cand[key] = val end
            end
        end
        -- Every per-type set sits inside Dispels' any-type set, so Dispels ANDed onto
        -- shown types changes nothing. Always a fresh set (never a vocabulary table).
        local typed = inc or anyType
        if typed then
            typed = TypesWithout(typed, exc)
            if not typed then clash = true end
            cand.includeDispelTypes = typed
            -- One shown type: every member carries it (with two, neither is certain).
            if nTypes == 1 then cats[#cats + 1] = typeKey end
        elseif exc then
            cand.excludeDispelTypes = exc
            -- Dispellable By You passes only debuffs of a dispellable type, so
            -- hiding all five leaves it nothing.
            if dispTok and exc.Magic and exc.Curse and exc.Disease and exc.Poison and exc.Bleed then
                clash = true
            end
        end
        -- PLAYER (Cast By You: you, your pet or vehicle) inside isFromPlayerOrPlayerPet
        -- = false (a shown Non-Player, or a hidden From Any Player) is always empty.
        if playerTok and cand.isFromPlayerOrPlayerPet == false then clash = true end
        if clash then return false end
        return { tokens = tokens, cand = cand }, cats
    end

    -- How category `class` relates to part p: "in" when every member belongs to it;
    -- nil when no member can; else "split" under `probe`, or the (p AND class,
    -- p AND NOT class) parts.
    local function Relate(profile, class, probe)
        if class.token then
            if HasToken(profile, class.token) then return "in" end
            local negTok = class.neg or ("!" .. class.token)
            if HasToken(profile, negTok) then return nil end
            if probe then return "split" end
            local a, b = CopyPart(profile), CopyPart(profile)
            a.tokens[#a.tokens + 1] = class.token
            b.tokens[#b.tokens + 1] = negTok
            return a, b
        end
        local cc = class.cand
        if not cc then return nil end
        local set = cc.includeDispelTypes
        if set then
            local inc, exc = profile.cand.includeDispelTypes, profile.cand.excludeDispelTypes
            if inc and not TypesWithout(inc, set) then return "in" end
            local place
            if inc then
                place = TypesAnd(inc, set)
            else
                place = set
            end
            if place then place = TypesWithout(place, exc) end
            if not place then return nil end
            if probe then return "split" end
            local a, b = CopyPart(profile), CopyPart(profile)
            a.cand.includeDispelTypes = place
            a.cand.excludeDispelTypes = nil
            if inc then
                b.cand.includeDispelTypes = TypesWithout(inc, set)
            else
                b.cand.excludeDispelTypes = MergeTypes(exc, set)
            end
            return a, b
        end
        local k, v = next(cc)
        if profile.cand[k] ~= nil then
            if profile.cand[k] == v then return "in" end
            return nil
        end
        if probe then return "split" end
        local a, b = CopyPart(profile), CopyPart(profile)
        a.cand[k] = v
        b.cand[k] = not v
        return a, b
    end

    local function MatchLink(profile, cats)
        local sorted = {}
        for index = 1, #cats do
            sorted[index] = cats[index]
        end
        table.sort(sorted)
        return {
            key = "and:" .. table.concat(sorted, "+"),
            tokens = profile.tokens,
            cand = next(profile.cand) and profile.cand or nil,
            cats = sorted,
        }
    end

    -- nil when Match All does not apply; empty when its picks can never match; else
    -- the painted splits (block order) followed by the rest of the group.
    local function MatchAllChain(conf)
        local rest, cats = MatchBase(conf)
        if rest == nil then return nil end
        if not rest then return {} end
        local chain = {}
        local entries = conf.fxList
        if entries then
            local inSet, seen = {}, {}
            for index = 1, #cats do
                inSet[cats[index]] = true
            end
            for index = 1, #entries do
                local entry = entries[index]
                local frame = entry.filters
                if frame and PAB_FxEntryActive(entry) then
                    -- First block wins: one naming a category the rest already
                    -- belongs to paints all of it, and no later block reaches it.
                    local hit = false
                    for jdx = 1, #DEBUFF_FILTER_ORDER do
                        local key = DEBUFF_FILTER_ORDER[jdx]
                        if frame[key] then
                            if inSet[key] then
                                hit = true
                            else
                                local class = ClassByKey(key)
                                if class and Relate(rest, class, true) == "in" then
                                    inSet[key] = true
                                    cats[#cats + 1] = key
                                    hit = true
                                end
                            end
                        end
                    end
                    if hit then break end
                    for jdx = 1, #DEBUFF_FILTER_ORDER do
                        local key = DEBUFF_FILTER_ORDER[jdx]
                        if frame[key] and not seen[key] then
                            seen[key] = true
                            local class = ClassByKey(key)
                            local a, b
                            if class then
                                a, b = Relate(rest, class)
                            end
                            if type(a) == "table" then
                                local pc = {}
                                for num = 1, #cats do
                                    pc[num] = cats[num]
                                end
                                pc[#pc + 1] = key
                                chain[#chain + 1] = MatchLink(a, pc)
                                rest = b
                            end
                        end
                    end
                end
            end
        end
        chain[#chain + 1] = MatchLink(rest, cats)
        return chain
    end

    -- The debuff chain for a bar: Match All when it applies, else the union.
    DebuffChainFor = function(conf)
        local chain = MatchAllChain(conf)
        if chain then return chain end
        return BuildChain(
            "HARMFUL",
            function(class)
                return ClassEnabled(class, false, conf)
                    or (PAB_FxSafeToForce(class) and PAB_FxWantsCategory(conf.fxList, class.key))
            end,
            DebuffCatchAllOn(conf),
            DebuffSubtractFn(conf)
        )
    end

    -- Options-page empty warning: Match All picks that can never match together.
    -- The builder's own test, so the two never disagree. ns.PAB_DebuffBarHasContent
    -- stays as it is (the one-shot EnsureBarEnable migration reads it).
    function mod.PAB_DebuffMatchEmpty(conf) return conf ~= nil and MatchBase(conf) == false end
end

-- MergeCandidateFilters (below) merges `extra` onto a copy of `base`, nil-safe both
-- ways: e.g. a chain-link's own candidateFilters (debuff class token) plus
-- BuffCandidateExtras' maxDuration.
--
-- Order-independent fingerprint of a candidate-filter table. Candidate payloads are
-- DECLARATION-FIXED on an existing group (SetAuraGroupCandidateFilters on a live
-- group does not retake), so any payload change must declare a fresh variant group
-- key. Number-keyed sets (spell ids) fingerprint as count:sum; string-keyed sets
-- (dispel names) join.
local function CandFP(castFrame)
    if not castFrame then return "-" end
    local keyList = {}
    for key in pairs(castFrame) do
        keyList[#keyList + 1] = key
    end
    table.sort(keyList)
    local parts = {}
    for index = 1, #keyList do
        local k = keyList[index]
        local v = castFrame[k]
        if type(v) == "table" then
            local first = next(v)
            if type(first) == "number" then
                local num, sum = 0, 0
                for ident in pairs(v) do
                    num = num + 1
                    sum = (sum + ident) % 2147483647
                end
                parts[#parts + 1] = k .. "=" .. num .. ":" .. sum
            else
                local nameList = {}
                for name in pairs(v) do
                    nameList[#nameList + 1] = tostring(name)
                end
                table.sort(nameList)
                parts[#parts + 1] = k .. "=" .. table.concat(nameList, "+")
            end
        else
            parts[#parts + 1] = k .. "=" .. tostring(v)
        end
    end
    return table.concat(parts, ",")
end

local function MergeCandidateFilters(base, extra)
    if not extra then return base end
    if not base then return extra end
    local result = {}
    for key, val in pairs(base) do
        result[key] = val
    end
    for key, val in pairs(extra) do
        if key == "excludeSpellIDs" and result[key] then
            -- Exclude maps UNION (never overwrite): the catch-all's subtract set
            -- and the extras' blacklist both survive.
            local m = {}
            for ident in pairs(result[key]) do
                m[ident] = true
            end
            for ident in pairs(val) do
                m[ident] = true
            end
            result[key] = m
        else
            result[key] = val
        end
    end
    return result
end

-- ApplyGroupConfig parameters: declaredSet is a per-container registry of every group
-- key ever declared (declared.debuffs for Debuff bars' class-token chain,
-- declared.buffs for the default Buffs bar's single "Show All Buffs" catch-all -- see
-- CreateBars for why buffs need ONE group alongside their slots). cfg is the bar's
-- settings table, read-only here, used only to resolve sortMethod/sortDirection;
-- SetAuraGroupSortMethod (unlike AddAuraGroup's sortMethod field) requires both
-- non-nil, so it's re-applied every pass, same as MaxFrameCount/Layout. extraCand
-- (optional) is candidateFilters merged onto every chain-link's own, threading
-- BuffCandidateExtras' maxDuration onto the Buffs catch-all without affecting Debuffs'
-- class-token chains (pass nil); re-applied live every pass via
-- SetAuraGroupCandidateFilters, since only the FILTER STRING is fixed at declaration.
--
-- Icon Effects Per-Filter Size override: icon size is entirely style-driven
-- (button:SetSize(style.width, style.height)); a group's own elementWidth/Height in
-- SetAuraGroupLayout feeds the FLOW MATH only, never resizes the button. A per-category
-- size needs its OWN style key, not a group-layout tweak. Keyed by size alone: the
-- variant is the bar's base style with width/height swapped, so two categories at the
-- same size share one variant, everything else riding along via the shallow copy.
-- Rebuilt unconditionally every pass (settings-apply frequency) rather than
-- fingerprint-cached.
local function EnsurePabSizedStyle(baseKey, size, shape)
    local base = AK.styles[baseKey]
    if not base then return baseKey end
    local variantKey = baseKey .. ":sz" .. tostring(size)
    local v = {}
    for key, val in pairs(base) do
        v[key] = val
    end
    -- Snapped like BuildStyle's own width/height (same button SetSize path, so a raw
    -- value reintroduces the 1px border/icon disagreement); the variant KEY stays
    -- keyed by the raw size. Shape-expand applies the same as BuildStyle's own
    -- iconSize -- base already carries iconShape/shapeMaskPath/etc via the shallow
    -- copy above, only width/height need recomputing for this variant's own size.
    v.width = PabSnap(PabShapedSize(size, shape))
    v.height = shape == "cropped" and PabSnap(mod.PAB_CroppedHeight(size, base)) or v.width
    AK.styles[variantKey] = v
    AK.RestyleSoon(variantKey)
    return variantKey
end

local function BuildGroupLayout(conf, gap, rowGap, size)
    rowGap = rowGap or gap
    local rawSize = size or conf.iconSize or 32
    size = PabSnap(PabShapedSize(rawSize, conf.iconShape))
    gap = PabSnap(gap)
    rowGap = PabSnap(rowGap)
    return {
        elementWidth = size,
        elementHeight = conf.iconShape == "cropped" and PabSnap(mod.PAB_CroppedHeight(rawSize, conf)) or size,
        elementSpacing = gap,
        lineSpacing = rowGap,
        -- ZERO on purpose: the engine's flow layout advances the cursor by
        -- elementSpacing AFTER every element, the last one of a group
        -- included, so a group boundary already carries one `gap`. Adding
        -- groupSpacing on top doubled it -- visible as a wider seam between
        -- the weapon-enchant cells and the first buff, and between the
        -- catch-all and spells groups.
        groupSpacing = 0,
        groupLineSpacing = rowGap,
    }
end

local function ApplyGroupConfig(
    boxHolder,
    chain,
    declaredSet,
    styleKey,
    effectiveMax,
    gap,
    rowGap,
    conf,
    extraCand
)
    local sortMethod = ResolveSortMethod(conf)
    local sortDirection = ResolveSortDirection(conf)
    -- elementSpacing = icon-to-icon gap in a row, and it also separates two
    -- groups on one line (see BuildGroupLayout's zero groupSpacing);
    -- lineSpacing = gap between wrapped rows within a group, tied to `rowGap`
    -- (defaults to `gap`) so row-to-row distance is overridable independently of
    -- icon-to-icon spacing (cfg.rowSpacing in the Settings Schema comment).
    -- Container-level padding is a THIRD, unrelated concept: the OUTER edge inset,
    -- fixed at 0 elsewhere and never affected by either.
    local isActive = {}
    for index = 1, #chain do
        local itemLink = chain[index]
        -- Size override, debuffs only: cfg.fxList is nil for buffs, so szOv is always
        -- nil there.
        local szOv = PAB_FxSizeFor(conf.fxList, itemLink.cats or itemLink.key)
        local layout = BuildGroupLayout(conf, gap, rowGap, szOv)
        -- Token strings are declaration-fixed too, so the effective key embeds the
        -- link's token set: a changed negation shape (subtract flips, class-set edits)
        -- declares a fresh variant instead of leaving a stale filter on the old group.
        -- link.key alone stays the fx CATEGORY identity (d.dmCat / PAB_FxSizeFor);
        -- a Match All link carries a category list instead (link.cats, named by its key).
        local effKey = itemLink.key .. "|" .. table.concat(itemLink.tokens, "")
        if szOv then effKey = effKey .. "|sz" end
        local linkStyleKey = szOv and EnsurePabSizedStyle(styleKey, szOv, conf.iconShape) or styleKey
        local candidateFilters
        if itemLink.cand then
            -- link.cand is from the shared class vocabulary -- copy it so the merges
            -- below never mutate it.
            candidateFilters = {}
            for key, val in pairs(itemLink.cand) do
                candidateFilters[key] = val
            end
        end
        candidateFilters = MergeCandidateFilters(candidateFilters, itemLink.excludeCand)
        candidateFilters = MergeCandidateFilters(candidateFilters, extraCand)
        -- Candidate payloads are declaration-fixed (see CandFP): when a link's payload
        -- changes on a live container (catch-all subtracts, buff filter subtract sets,
        -- Has Duration) its fingerprint picks the group variant. A fresh fingerprint
        -- declares a fresh variant and the stale one parks at 0 in the active-set sweep
        -- below, like any disabled class group. Fingerprints REUSE their variant, so
        -- toggling a subtract off and back on reuses the same engine groups rather than
        -- minting a new 10-button batch per flip.
        local fp = CandFP(candidateFilters)
        local meta = declaredSet["__cand|" .. effKey]
        if not meta then
            meta = { n = 0, map = {} }
            declaredSet["__cand|" .. effKey] = meta
        end
        local variant = meta.map[fp]
        if not variant then
            variant = meta.n
            meta.map[fp] = variant
            meta.n = meta.n + 1
        end
        if variant > 0 then effKey = effKey .. "#" .. variant end
        isActive[effKey] = true
        if not declaredSet[effKey] then
            local catKey = itemLink.cats or itemLink.key
            AK.AddGroupToContainer(boxHolder, {
                key = effKey,
                filter = itemLink.tokens,
                style = linkStyleKey,
                maxFrameCount = 0, -- real count applied right below, matches the sibling module's declare-then-set order
                candidateFilters = candidateFilters,
                sortMethod = sortMethod,
                sortDirection = sortDirection,
                layout = layout,
                -- Icon Effects Per-Filter: stamps this button's category (matched
                -- against fxList blocks by PAB_ApplyDmFx) and arms the glow/border
                -- overlay inside the one legal creation window. style.applyExtra runs
                -- BEFORE extraInit at creation (CludesUI_AuraKit.lua's
                -- MakeInitializer), so the first applyExtra pass sees d.dmCat == nil
                -- harmlessly and this re-arms it right after.
                extraInit = function(btnFrame, skinData, style)
                    skinData.dmCat = catKey
                    PAB_ApplyDmFx(btnFrame, skinData, style, true)
                end,
            })
            declaredSet[effKey] = true
        end
        -- Hidden links (subtracted classes) stay declared so their chain negations
        -- keep excluding them from the catch-all, but render nothing themselves.
        CUI.AuraKit.SetGroupCap(boxHolder, effKey, itemLink.hidden and 0 or effectiveMax)
        boxHolder:SetAuraGroupLayout(effKey, layout)
        boxHolder:SetAuraGroupCandidateFilters(effKey, candidateFilters)
        if sortMethod ~= nil and sortDirection ~= nil then
            boxHolder:SetAuraGroupSortMethod(effKey, sortMethod, sortDirection)
        end
    end

    -- Zero out any previously-declared group that fell out of the active chain (class
    -- disabled, or a candidate payload change superseded its variant). Stays declared,
    -- just hidden: it cannot be un-declared. "__cand|" entries are generation
    -- metadata, not group keys.
    for key in pairs(declaredSet) do
        if not isActive[key] and key:sub(1, 7) ~= "__cand|" then
            CUI.AuraKit.SetGroupCap(boxHolder, key, 0)
        end
    end
end

-- Retire a container we are abandoning. AuraContainer frames are PERMANENT and a
-- declared group can NEVER be un-declared (the sweep above can only zero one), so
-- AK.ReleaseContainer hides the frame but leaves every group live on it at whatever
-- frame count it last had -- anything that shows that frame again renders the old
-- content. Zero what we know about while we still hold the declared set; "spells"
-- is declared outside the chain, so it goes by name. pcall: zeroing a key this
-- container never declared is not worth an error.
local function RetireContainer(boxHolder, declaredSet)
    if not boxHolder then return end
    if declaredSet then
        for key in pairs(declaredSet) do
            if key:sub(1, 7) ~= "__cand|" then pcall(CUI.AuraKit.SetGroupCap, boxHolder, key, 0) end
        end
    end
    pcall(CUI.AuraKit.SetGroupCap, boxHolder, "spells", 0)
    AK.ReleaseContainer(boxHolder)
end

Inner.ApplyGroupConfig, Inner.BuildGroupLayout = ApplyGroupConfig, BuildGroupLayout
Inner.DebuffChainFor, Inner.MergeCandidateFilters = DebuffChainFor, MergeCandidateFilters
Inner.RetireContainer = RetireContainer
Inner.broken = false
