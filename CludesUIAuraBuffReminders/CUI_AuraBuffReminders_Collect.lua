if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_AuraBuffReminders_Collect.lua
--
--  Layout and ShowIcon, and the collectors of the Raid Buffs, Auras and
--  Consumables sections.
--  Reads the earlier AuraBuff Reminders files through ns._abrInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._abrInternals
-- CludesUIAuraBuffReminders.lua or an earlier AuraBuff Reminders file
-- failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local floor, min, abs = math.floor, math.min, math.abs

local _B, DEFAULT_TEXT_COLOR, REMIND = Inner._B, Inner.DEFAULT_TEXT_COLOR, Inner.EABR
local GetPlayerClass, GetTextAnchorPoints = Inner.GetPlayerClass, Inner.GetTextAnchorPoints
local InCombat, InPvPInstance, isSecret = Inner.InCombat, Inner.InPvPInstance, Inner.isSecret
local Known, NON_SECRET_SPELL_IDS = Inner.Known, Inner.NON_SECRET_SPELL_IDS
local CursorAttachActive = Inner.CursorAttachActive
local ResolveFontPath, SetABRFont, ShortLabel = Inner.ResolveFontPath, Inner.SetABRFont, Inner.ShortLabel
local Tex, _preCombatOwnOnRaidCache = Inner.Tex, Inner._preCombatOwnOnRaidCache
local BuffExistsOnAnyGroupMember = Inner.BuffExistsOnAnyGroupMember
local CountGroupBuffCoverage, GetStanceState = Inner.CountGroupBuffCoverage, Inner.GetStanceState
local IsAnyShapeshiftFormActive = Inner.IsAnyShapeshiftFormActive
local IsUnderDuration, PlayerHasAuraByID = Inner.IsUnderDuration, Inner.PlayerHasAuraByID
local PlayerHasSelfCastAuraByID = Inner.PlayerHasSelfCastAuraByID
local PlayerOwnBuffOnAnyGroupMember = Inner.PlayerOwnBuffOnAnyGroupMember
local _IMBUE_EXCLUDE_SPELLS, AURAS = Inner._IMBUE_EXCLUDE_SPELLS, Inner.AURAS
local CachedGetItemCount, DTB_SPELL_ID = Inner.CachedGetItemCount, Inner.DTB_SPELL_ID
local INKY_BLACK_ITEM, PALADIN_RITES = Inner.INKY_BLACK_ITEM, Inner.PALADIN_RITES
local PARTNERED_TRINKET, PlayerHasBuffByName = Inner.PARTNERED_TRINKET, Inner.PlayerHasBuffByName
local PlayerHasFlaskBuff = Inner.PlayerHasFlaskBuff
local PlayerHasInkyBlackness, PlayerHasWellFed = Inner.PlayerHasInkyBlackness, Inner.PlayerHasWellFed
local RAID_BUFFS, ROGUE_POISONS, RUNE_BUFF_IDS = Inner.RAID_BUFFS, Inner.ROGUE_POISONS, Inner.RUNE_BUFF_IDS
local SHAMAN_IMBUES, SHAMAN_SHIELDS = Inner.SHAMAN_IMBUES, Inner.SHAMAN_SHIELDS
local AcquireEntry, activeIcons, ApplyGlow = Inner.AcquireEntry, Inner.activeIcons, Inner.ApplyGlow
local ApplySetup, GetOrCreateIcon, ICON_SIZE = Inner.ApplySetup, Inner.GetOrCreateIcon, Inner.ICON_SIZE
local iconPool, RemoveGlow = Inner.iconPool, Inner.RemoveGlow

local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(val) saved = val end
-- Hunter's Mark combat state: true on REGEN_DISABLED, cleared on cast/combat
-- end; OOC falls back to target debuff check.
local _huntersMarkNeeded = false
Inner.huntersMarkSetters[#Inner.huntersMarkSetters + 1] = function(val) _huntersMarkNeeded = val end
local iconAnchor
Inner.iconAnchorSetters[#Inner.iconAnchorSetters + 1] = function(val) iconAnchor = val end
local cursorAnchor
Inner.cursorAnchorSetters[#Inner.cursorAnchorSetters + 1] = function(val) cursorAnchor = val end

-------------------------------------------------------------------------------
--  Core Refresh Logic
-------------------------------------------------------------------------------

local function HideAllIcons()
    if InCombatLockdown() then return end -- cannot hide SecureActionButtons after lockdown begins
    -- Sweep the WHOLE pool, never just activeIcons: a combat fade leaves icons
    -- shown at alpha 0, and any window where the list rebuilds without those
    -- frames orphans them -- shown, invisible, still hover/tooltip-live (field:
    -- an invisible stuck Augment Rune). The pool is a dozen frames and this
    -- runs on OOC edges only, so the sweep costs nothing; alpha resets here so
    -- a swept frame can never carry a stale fade into its next show.
    for _, button in pairs(iconPool) do
        if button then
            RemoveGlow(button)
            REMIND.ClearEatingVisual(button)
            button._text:SetText("")
            button._text:SetAlpha(1)
            button._icon:SetDesaturated(false)
            button:SetAlpha(1)
            button:Hide()
        end
    end
    wipe(activeIcons)
end

-- iconAnchor is pinned by its grow edge (CENTER, LEFT or RIGHT) and the icons
-- hang off that same edge, so resizing it never moves them.
local function ResizeAnchorCentered(newW, newH)
    if not iconAnchor or InCombatLockdown() then return end
    iconAnchor:SetSize(newW, newH)
end

local _layoutScratch = {} -- reused each call
-- The last out-of-combat row: its anchor point, first slot, text offset,
-- icon size, spacing, opacity and how many of its slots the secure buttons
-- take (the beacon icons follow them).
local _layoutGeom = {}
local function LayoutIcons()
    if InCombatLockdown() then
        -- The reminder buttons are secure, so the row stays as the last pass
        -- left it. The beacon icons are plain frames, and one that shows in
        -- combat (a Solo Shuffle round) would otherwise keep the spot an
        -- earlier row gave it, over whatever sits there now: the shown beacons
        -- hang after that row at its pitch until the next pass lays it out again.
        local g = _layoutGeom
        if not g.pt or not _B.icons then return end
        if saved and CursorAttachActive(saved.profile.display) and cursorAnchor then return end
        local index = g.fixed
        for _, ident in ipairs(_B.ALL or {}) do
            local frame = _B.iconState and _B.iconState[ident] and _B.icons[ident]
            if frame then
                index = index + 1
                frame:SetSize(g.sz, g.iconH or g.sz)
                frame:SetAlpha(g.alpha)
                frame:ClearAllPoints()
                frame:SetPoint(g.pt, iconAnchor, g.pt, g.startX + (index - 1) * (g.sz + g.spacing), g.yOff)
            end
        end
        return
    end
    -- Merges beacon icons into the layout (one continuous row); beacon logic itself is untouched, just included here for positioning.
    local allIcons = _layoutScratch
    wipe(allIcons)
    -- Provider raid-buff button is a separate UIParent secure button; slot 0
    -- of the row when shown.
    if REMIND._providerCastVisible and REMIND._providerCastBtn then
        allIcons[#allIcons + 1] = REMIND._providerCastBtn
    end
    for _, button in ipairs(activeIcons) do
        allIcons[#allIcons + 1] = button
    end
    local fixed = #allIcons
    local beaconsOnCursor = saved and CursorAttachActive(saved.profile.display) and cursorAnchor
    if _B.icons and not beaconsOnCursor then
        for _, ident in ipairs(_B.ALL or {}) do
            if _B.iconState and _B.iconState[ident] and _B.icons[ident] then
                allIcons[#allIcons + 1] = _B.icons[ident]
            end
        end
    end
    local total = #allIcons
    if total == 0 then
        _layoutGeom.fixed = 0
        return
    end
    local display = saved.profile.display
    local spacing = display.iconSpacing or 8
    local baseScale = display.scale or 1.0
    local iconSz = floor(ICON_SIZE * baseScale + 0.5)
    local iconH = iconSz
    if display.iconShape and display.iconShape ~= "none" then
        iconSz, iconH = mod.IconDimensions(iconSz, display)
    end
    local totalW = (total * iconSz) + ((total - 1) * spacing)
    local textH = 0
    if display.showText then textH = (display.textSize or 11) + abs(display.textYOffset or -2) end
    -- Icons hang off the anchor's grow edge. Center-grow spreads them symmetrically so the row's center stays fixed
    -- as icons are added/removed; +textH/2 keeps the row at the icon+text box's top, matching the combat pool.
    -- Grow Right/Left hang them from the TOPLEFT/TOPRIGHT corner so that edge stays fixed instead.
    local pt, startX, yOff = "CENTER", -(totalW / 2) + (iconSz / 2), textH / 2
    if display.growDirection == "RIGHT" then
        pt, startX, yOff = "TOPLEFT", 0, 0
    elseif display.growDirection == "LEFT" then
        pt, startX, yOff = "TOPRIGHT", -(total - 1) * (iconSz + spacing), 0
    end
    local g = _layoutGeom
    g.pt, g.startX, g.yOff, g.sz, g.spacing, g.alpha, g.fixed =
        pt, startX, yOff, iconSz, spacing, display.opacity or 1.0, fixed
    if display.iconShape and display.iconShape ~= "none" then
        g.iconH = iconH
    elseif g.iconH then
        g.iconH = nil
    end
    for index, button in ipairs(allIcons) do
        button:SetSize(iconSz, iconH)
        button:SetAlpha(display.opacity or 1.0)
        -- This layout is OOC-only, so treating every entry as protected also
        -- covers the provider/main secure buttons without needing pool scans.
        REMIND.ApplyIconBorder(button, true)
        REMIND.SizeIconQuality(button, iconSz)
        REMIND.SizeIconBagCount(button, iconSz)
        button:ClearAllPoints()
        button:SetPoint(pt, iconAnchor, pt, startX + (index - 1) * (iconSz + spacing), yOff)
    end
    -- Size the anchor to the row so the unlock mode overlay covers it.
    ResizeAnchorCentered(totalW, iconH + textH)
end

local function ShowIcon(iconIdx, m)
    local button = GetOrCreateIcon(iconIdx)
    button._dismissKey = m.dismissKey or nil
    button._petCycleTotal = m.petCycleTotal or nil
    button._foreverGroup = m.foreverGroup
    button._requestKey = m.requestKey or nil
    button._requestName = m.requestName or nil
    -- Right-click is passed through to whatever's behind (e.g. camera drag)
    -- except on multi-pet cycle buttons and clickable spell groups.
    -- Left-click is passed through too on a groupmate's raid buff the player
    -- cannot cast, unless Click to Request Buff gives it one (the
    -- middle-click dismiss stays). Click-routing changes are combat-protected,
    -- same as the attribute writes below, so this only ever runs OOC.
    local receiver = REMIND.IsReceiverRaidBuff(m) and not m.requestKey
    if not InCombat() then
        local pass = (receiver and 1 or 0) + ((m.petCycleTotal or button._foreverGroup) and 0 or 2)
        if button._passButtons ~= pass then
            button._passButtons = pass
            if pass == 3 then
                securecallfunction(button.SetPassThroughButtons, button, "LeftButton", "RightButton")
            elseif pass == 2 then
                securecallfunction(button.SetPassThroughButtons, button, "RightButton")
            elseif pass == 1 then
                securecallfunction(button.SetPassThroughButtons, button, "LeftButton")
            else
                securecallfunction(button.SetPassThroughButtons, button)
            end
        end
    end
    REMIND.SetIconHighlight(button, not receiver)
    ApplySetup(button, m)
    local display = saved.profile.display
    local baseScale = display.scale or 1.0
    local iconSz = floor(ICON_SIZE * baseScale + 0.5)
    ApplyGlow(button, display, iconSz)
    REMIND.ApplyEatingVisual(button, m)
    REMIND.ApplyIconExpiry(button, m)
    REMIND.ApplyIconQuality(button, (not m.isEating) and m.qualityAtlas or nil)
    if m.groupTotal then
        REMIND.ApplyIconGroupCoverage(button, m.groupHave, m.groupTotal)
    else
        REMIND.ApplyIconBagCount(
            button,
            (not m.isEating) and m.bagCount or nil,
            (not m.isEating) and m.desaturated or nil,
            (not m.isEating) and m.substitute or nil,
            m.spellRank
        )
    end
    if display.showText and not m.isEating then
        local tc = display.textColor or DEFAULT_TEXT_COLOR
        local fontFile = ResolveFontPath(display.nameFont)
        local textSize = display.textSize or 11
        local xOff = display.textXOffset or 0
        local yOff = display.textYOffset or -2
        SetABRFont(button._text, fontFile, textSize)
        button._text:ClearAllPoints()
        local tp, ip = GetTextAnchorPoints(display)
        button._text:SetPoint(tp, button, ip, xOff, yOff)
        button._text:SetTextColor(tc.r, tc.g, tc.b, 1)
        button._text:Show()
    else
        button._text:SetText("")
        button._text:Hide()
    end
    button:Show()
    activeIcons[#activeIcons + 1] = button
end

local function CollectRaidBuffs(missing, classFile, instanceNow, combatNow)
    local rb = saved.profile.raidBuffs
    do
        if not REMIND.SectionShows(rb.whereToShow, instanceNow) then return end
        local _, iType = IsInInstance()
        local pvpNow = (iType == "pvp" or iType == "arena")
        local sw = rb.showWhen or {}
        local othersMissing = sw.othersMissing ~= false
        local iAmMissing = sw.iAmMissing == true
        -- Receiver view ("I am missing others' buffs") only scans group
        -- composition when opted in and actually grouped -- the default case
        -- stays allocation-free.
        local groupClasses
        if iAmMissing and (IsInGroup() or IsInRaid()) then groupClasses = REMIND.BuildGroupClassSet() end
        for _, buffRec in ipairs(RAID_BUFFS) do
            if rb.enabled[buffRec.key] and not (buffRec.noPvP and pvpNow) then
                local iCast = (buffRec.class == classFile) and Known(buffRec.castSpell)
                -- Provider view when I can cast it; receiver view when I can't
                -- but a groupmate of the right class can (and my class benefits).
                local doReceiver = not iCast
                    and iAmMissing
                    and buffRec.check == "raid"
                    and groupClasses
                    and groupClasses[buffRec.class]
                    and REMIND.PlayerBenefitsFromBuff(buffRec)
                if iCast or doReceiver then
                    -- In combat, skip buffs whose IDs are not all whitelisted
                    local checkable = true
                    if combatNow then
                        if buffRec.check == "huntersMark" then
                            checkable = true -- uses state flag, no aura reading needed
                        else
                            for _, ident in ipairs(buffRec.buffIDs) do
                                if not NON_SECRET_SPELL_IDS[ident] then
                                    checkable = false
                                    break
                                end
                            end
                        end
                    end
                    if checkable then
                        local isMissing = false
                        local groupHave, groupSize
                        if iCast then
                            if buffRec.check == "huntersMark" then
                                isMissing = combatNow and _huntersMarkNeeded
                            elseif
                                othersMissing
                                and buffRec.check == "raid"
                                and (IsInGroup() or IsInRaid())
                            then
                                groupHave, groupSize =
                                    CountGroupBuffCoverage(buffRec.buffIDs, buffRec.benefit)
                                isMissing = groupSize > 0 and groupHave < groupSize
                            else
                                isMissing = not PlayerHasAuraByID(buffRec.buffIDs, "raidbuff")
                            end
                        else
                            -- Receiver view: only whether the player personally lacks it.
                            isMissing = not PlayerHasAuraByID(buffRec.buffIDs, "raidbuff")
                        end
                        if isMissing then
                            local entry = AcquireEntry()
                            local sname = _G._CUABR_SpellName(buffRec.castSpell, buffRec.name)
                            entry.spellID = buffRec.castSpell
                            entry.label = ShortLabel(sname)
                            if buffRec.check == "huntersMark" then entry.unit = "target" end
                            entry.cat = "raidbuff"
                            entry.data = buffRec
                            entry.dismissKey = buffRec.key and ("raidbuff:" .. buffRec.key) or nil
                            if groupSize then
                                entry.groupHave = groupHave
                                entry.groupTotal = groupSize
                            end
                            if doReceiver then
                                -- Receiver reminders: texture mode, no cast; a
                                -- left-click may ask the group for the buff.
                                entry.mode = "texture"
                                entry.texture = Tex(buffRec.castSpell)
                                if rb.requestOnClick then
                                    entry.requestKey = buffRec.key
                                    entry.requestName = sname
                                end
                            else
                                entry.mode = "spell"
                            end
                            missing[#missing + 1] = entry
                        end
                    end
                end
            end
        end
    end
end

local function CollectAuras(missing, classFile, specID, instanceNow, combatNow)
    local au = saved.profile.auras
    do
        local auraSectionShows = REMIND.SectionShows(au.whereToShow, instanceNow)
        for _, auraInfo in ipairs(AURAS) do
            if auraInfo.standalone then
            -- Handled by standalone system, skip
            elseif
                au.enabled[auraInfo.key]
                and (auraInfo.class == classFile)
                and (not auraInfo.combatOnly or InCombat())
                and ((auraInfo.key == "soulstone" and REMIND.SectionShows(
                    saved.profile.consumables.warlockWhereToShow,
                    instanceNow
                )) or (auraInfo.key ~= "soulstone" and auraSectionShows))
                and ((auraInfo.isStance and GetStanceState(auraInfo.castSpell)) or (not auraInfo.isStance and Known(
                    auraInfo.castSpell
                )))
                and not (auraInfo.notIfKnown and Known(auraInfo.notIfKnown))
                and not (auraInfo.requireTalent and not Known(auraInfo.requireTalent))
                and not (auraInfo.noPvP and InPvPInstance())
            then
                local specMatches = true
                if auraInfo.specs then
                    specMatches = false
                    for _, spec in ipairs(auraInfo.specs) do
                        if spec == specID then
                            specMatches = true
                            break
                        end
                    end
                end
                if specMatches then
                    -- Skip auras that require instance + group when not in both
                    if
                        auraInfo.requireInstanceGroup and (not instanceNow or not (IsInGroup() or IsInRaid()))
                    then
                        specMatches = false
                    end
                    -- Skip auras that require a group when solo
                    if auraInfo.requireGroup and not (IsInGroup() or IsInRaid()) then specMatches = false end
                end
                if specMatches then
                    -- Restricted contexts (combat / M+): only track reminders
                    -- whose detection survives the aura lock -- stances/forms
                    -- (the shapeshift API is unrestricted) or auras whose buff
                    -- IDs are all whitelisted. combatOk entries keep their own
                    -- snapshot machinery. Everything else is skipped to avoid
                    -- false flashes.
                    local checkable = true
                    if combatNow then
                        if auraInfo.isStance or auraInfo.formSpellIDs then
                            checkable = true
                        elseif auraInfo.combatOk == false then
                            checkable = false
                        elseif auraInfo.buffIDs and auraInfo.buffIDs[1] then
                            for _, ident in ipairs(auraInfo.buffIDs) do
                                if not NON_SECRET_SPELL_IDS[ident] then
                                    checkable = false
                                    break
                                end
                            end
                        else
                            checkable = false
                        end
                    end
                    if checkable then
                        local isMissing = false
                        if auraInfo.check == "mineOnRaid" then
                            if combatNow then
                                isMissing = false
                            else
                                isMissing = not BuffExistsOnAnyGroupMember(auraInfo.buffIDs)
                                if not (IsInGroup() or IsInRaid()) then isMissing = false end
                            end
                        elseif auraInfo.check == "ownOnRaid" then
                            if auraInfo.key == "som" then
                                -- This cache is seeded OOC and a successful player cast
                                -- can set it in combat; nil means unknown/suppress. A
                                -- miss only reminds while someone is in reach to take it.
                                isMissing = (
                                    REMIND._ownOtherAuraCache[369459] == false
                                    or REMIND.OwnOtherAuraNeedsRebuff(369459, "aura")
                                )
                                    and REMIND.AnyReachableGroupMember()
                            elseif combatNow then
                                local cached = _preCombatOwnOnRaidCache[auraInfo.buffIDs[1]]
                                isMissing = (cached == false)
                            else
                                isMissing = not PlayerOwnBuffOnAnyGroupMember(auraInfo.buffIDs)
                            end
                            if not (IsInGroup() or IsInRaid()) then isMissing = false end
                        elseif auraInfo.check == "ownGroupOrSelf" then
                            local hasOwnBuff = REMIND.PlayerOwnBuffOnGroupOrSelf(auraInfo.buffIDs)
                            isMissing = hasOwnBuff == false
                            if isMissing and auraInfo.key == "soulstone" then
                                -- On cooldown = nothing to cast, so no reminder. isActive is
                                -- NeverSecret; duration can be secret in restricted content,
                                -- where the reminder stays hidden until the next refresh edge.
                                -- No event watches the cooldown: a one-shot timer covers the
                                -- idle expiry, and the fight-end refresh (ENCOUNTER_END /
                                -- REGEN_ENABLED) already covers a boss-reset clear.
                                local cdInfo = C_Spell.GetSpellCooldown(auraInfo.castSpell)
                                local remaining
                                if cdInfo and cdInfo.isActive then
                                    -- Ignore the ordinary GCD.
                                    local dur = cdInfo.duration
                                    if isSecret(dur) then
                                        isMissing = false
                                    elseif dur and dur > 1.5 then
                                        isMissing = false
                                        local start = cdInfo.startTime
                                        if not isSecret(start) and type(start) == "number" then
                                            remaining = start + dur - GetTime()
                                        end
                                    end
                                end
                                REMIND.ArmSoulstoneCooldownRefresh(remaining)
                            end
                        elseif auraInfo.check == "playerSelfCast" then
                            isMissing = not PlayerHasSelfCastAuraByID(auraInfo.buffIDs)
                        elseif auraInfo.isStance then
                            -- Stance is a shapeshift form: hide once it's the active stance
                            local _, isActive = GetStanceState(auraInfo.castSpell)
                            isMissing = not isActive
                        else
                            -- Use instance-specific buff list if available and in instance
                            local checkIDs = (instanceNow and auraInfo.instanceBuffIDs) or auraInfo.buffIDs
                            -- When aura reads are restricted (PvP, combat, M+),
                            -- fall back to scanning the shapeshift form bar for
                            -- form-based auras whose buff IDs aren't readable.
                            if auraInfo.formSpellIDs and (combatNow or InPvPInstance()) then
                                isMissing = not IsAnyShapeshiftFormActive(auraInfo.formSpellIDs)
                            else
                                local hasIt = PlayerHasAuraByID(checkIDs, "aura")
                                -- Some auras (e.g. Devotion Aura) go fully secret
                                -- rather than merely duration/expiration-secret
                                -- when their source is ambiguous (another
                                -- provider of the same aura in the party); the ID
                                -- lookup then can't see it at all. Fall back to a
                                -- name scan before declaring it missing.
                                if not hasIt and auraInfo.nameFallback then
                                    hasIt = PlayerHasBuffByName(auraInfo.nameFallback)
                                end
                                isMissing = not hasIt
                            end
                        end
                        if isMissing then
                            local entry = AcquireEntry()
                            entry.mode = "spell"
                            entry.spellID = auraInfo.castSpell
                            entry.label = ShortLabel(_G._CUABR_SpellName(auraInfo.castSpell, auraInfo.name))
                            entry.cat = "aura"
                            entry.data = auraInfo
                            entry.dismissKey = "aura:" .. auraInfo.key
                            missing[#missing + 1] = entry
                        end
                    end
                end
            end
        end
    end
end

-- Weapon-enchant reminders shared by the OOC and restricted (M+/combat)
-- passes -- the enchant summary API is combat-safe. Hung on EABR.
function REMIND.EmitWeaponEnchantReminders(missing, collector)
    local hasMH, mhExpire, _, _, hasOH, ohExpire = REMIND.WeaponEnchants()
    for index = 1, 2 do
        local slot, has, expire
        -- Plain if/else, not "cond and a or b": that idiom silently falls
        -- through to b whenever a (hasMH) is false, corrupting slot 16.
        if index == 1 then
            slot, has, expire = 16, hasMH, mhExpire
        else
            slot, has, expire = 17, hasOH, ohExpire
        end
        local region = REMIND._resolved.we[slot]
        local category = region.cat
        local shouldRemind = false
        if category and not has then
            shouldRemind = true
        elseif category and has and expire and expire > 0 then
            local expireTime = expire / 1000 + GetTime()
            if IsUnderDuration(3600, expireTime, "consumable") then shouldRemind = true end
        end
        if shouldRemind and region.itemID and (collector.showWithoutItem ~= false or region.hasBags) then
            local bestItemID = region.itemID
            local entry = AcquireEntry()
            entry.mode = "macro"
            entry.macro = "/use item:" .. bestItemID .. "\n/use " .. slot
            entry.texture = C_Item.GetItemIconByID(bestItemID) or 134400
            -- Localizes the full slot name THEN shortens: ShortLabel truncates on whitespace (English -> Main/Off, space-less locales like zhTW stay intact). L() on the pre-truncated word would collide with the generic Off (disabled) translation.
            entry.label = ShortLabel(CludesUI.L(slot == 16 and "Main Hand" or "Off Hand"))
            entry.tooltipItem = bestItemID
            entry.qualityAtlas = REMIND.GetItemQualityAtlas(bestItemID)
            entry.bagCount = CachedGetItemCount(bestItemID)
            entry.desaturated = not region.hasBags
            entry.cat = "consumable"
            entry.dismissKey = "consumable:weapon_enchant_" .. slot
            missing[#missing + 1] = entry
        end
    end
end

-- The Inky Black Potion reminder's zone test reads the player's map from
-- PLAYER_MAP_CHANGED, so a refresh never asks the game for it (the game's
-- own map lookup misbehaves in places, Murder Row on 12.1.5). The watch runs
-- only while that reminder has zones listed and can show; it reads the map
-- once when it starts and after each loading screen, and a map change that
-- moves the player into or out of the listed zones asks for one refresh.
local inkyIndex = { on = false, key = "0", inZone = false }

local function InkyMapRead(mapID)
    inkyIndex.key = tostring(mapID or 0)
    local nowIn = (inkyIndex.set and inkyIndex.set[inkyIndex.key]) and true or false
    if nowIn ~= inkyIndex.inZone then
        inkyIndex.inZone = nowIn
        Inner.RequestRefresh()
    end
end

local function InkyMapWatch(wanted)
    if wanted == inkyIndex.on then return end
    inkyIndex.on = wanted
    local frame = inkyIndex.frame
    if not wanted then
        frame:UnregisterAllEvents()
        return
    end
    if not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", function(_, evt, _, newMapID)
            if evt == "PLAYER_MAP_CHANGED" then
                InkyMapRead(newMapID)
            else
                InkyMapRead(C_Map.GetBestMapForUnit("player"))
            end
        end)
        inkyIndex.frame = frame
    end
    frame:RegisterEvent("PLAYER_MAP_CHANGED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    inkyIndex.key = tostring(C_Map.GetBestMapForUnit("player") or 0)
end

local function CollectConsumables(missing, classFile, specID, instanceNow, inKeystone, combatNow, pvpNow)
    local collector = saved.profile.consumables
    -- Class specials (poisons/rites/imbues/shields) follow the "Where to Show"
    -- of the player's class section.
    local specialFields = REMIND.SPECIALS[classFile]
    local specialsActive = REMIND.SectionShows(
        REMIND.SpecialsWhere(collector, specialFields and specialFields.where),
        instanceNow
    )
    -- The trackable subset (weapon enchants, poisons, rites, imbues, Earth
    -- Shield) runs in combat / M+ too; where reminders appear is governed
    -- per-section by "Where to Show". Non-trackable emitters below either
    -- self-suppress in restricted contexts (flask/food/inky/rune) or carry
    -- their own combat gate.
    do
        -- Rebuilds the bag/equip-derived item cache only when inputs changed (bags, weapon, preferred-item setting); a clean refresh is 3 scalar compares. Resolved inside instances, or in the open world when the consumables section shows there; the dirty flag persists until the next eligible refresh consumes it.
        local needResolve = instanceNow and not pvpNow
        if not needResolve and not pvpNow then
            local ow = collector.whereToShow
            needResolve = (not ow) or (ow.open_world ~= false)
        end
        if needResolve then REMIND.ResolveConsumables() end

        -- === SPECIALS (per-class "Where to Show") ===
        if specialsActive then
            -- Rogue Poisons: unified scan counts active per category vs required (1 each, 2 with Dragon-Tempered Blades); shows the first enabled+known+missing poison per deficient category.
            if classFile == "ROGUE" then
                local activeL, activeNL = 0, 0
                local knownL, knownNL = 0, 0
                local missingL, missingNL = nil, nil
                for _, poison in ipairs(ROGUE_POISONS) do
                    if Known(poison.castSpell) then
                        local isLethal = (poison.cat == "lethal")
                        if isLethal then
                            knownL = knownL + 1
                        else
                            knownNL = knownNL + 1
                        end
                        local auraInfo = C_UnitAuras.GetPlayerAuraBySpellID(poison.castSpell)
                        local active = auraInfo
                            and not IsUnderDuration(auraInfo.duration, auraInfo.expirationTime, "special")
                        if active then
                            if isLethal then
                                activeL = activeL + 1
                            else
                                activeNL = activeNL + 1
                            end
                        elseif collector.enabled[poison.key] then
                            if isLethal and not missingL then
                                missingL = poison
                            elseif not isLethal and not missingNL then
                                missingNL = poison
                            end
                        end
                    end
                end
                local hasDTB = IsPlayerSpell(DTB_SPELL_ID)
                local reqL = min(knownL, hasDTB and 2 or 1)
                local reqNL = min(knownNL, hasDTB and 2 or 1)
                if missingL and activeL < reqL then
                    local entry = AcquireEntry()
                    entry.mode = "spell"
                    entry.spellID = missingL.castSpell
                    entry.label = ShortLabel(_G._CUABR_SpellName(missingL.castSpell, missingL.name), "ROGUE")
                    entry.cat = "consumable"
                    entry.data = missingL
                    entry.dismissKey = "consumable:rogue_lethal"
                    missing[#missing + 1] = entry
                end
                if missingNL and activeNL < reqNL then
                    local entry = AcquireEntry()
                    entry.mode = "spell"
                    entry.spellID = missingNL.castSpell
                    entry.label =
                        ShortLabel(_G._CUABR_SpellName(missingNL.castSpell, missingNL.name), "ROGUE")
                    entry.cat = "consumable"
                    entry.data = missingNL
                    entry.dismissKey = "consumable:rogue_nonlethal"
                    missing[#missing + 1] = entry
                end
            end

            -- Paladin Rites
            if classFile == "PALADIN" then
                for _, rite in ipairs(PALADIN_RITES) do
                    if collector.enabled[rite.key] and Known(rite.castSpell) then
                        local hasMH, mhExpire = REMIND.WeaponEnchants()
                        local show = false
                        if not hasMH then
                            show = true
                        elseif
                            mhExpire
                            and mhExpire > 0
                            and IsUnderDuration(3600, mhExpire / 1000 + GetTime(), "consumable")
                        then
                            show = true
                        end
                        if show then
                            local entry = AcquireEntry()
                            local spellName = _G._CUABR_SpellName(rite.castSpell, rite.name)
                            entry.mode = "macro"
                            entry.spellID = rite.castSpell
                            entry.macro = "/cast " .. spellName .. "\n/use 16"
                            entry.label = ShortLabel(_G._CUABR_SpellName(rite.castSpell, rite.name))
                            entry.cat = "consumable"
                            entry.data = rite
                            entry.dismissKey = "consumable:" .. rite.key
                            missing[#missing + 1] = entry
                            break -- rites are mutually exclusive weapon enchants
                        end
                    end
                end
            end

            -- Shaman Imbues: matches each imbue's wepEnchID against both weapon slots; the enchant summary carries the specific enchant ID per hand (4th/8th return values).
            if classFile == "SHAMAN" then
                local hasMH, mhExpire, _, mhEnchID, hasOH, ohExpire, _, ohEnchID = REMIND.WeaponEnchants()
                for _, imbue in ipairs(SHAMAN_IMBUES) do
                    if
                        collector.enabled[imbue.key]
                        and Known(imbue.castSpell)
                        and (not imbue.requireShield or REMIND.HasShieldEquipped())
                    then
                        local found = false
                        if imbue.wepEnchID then
                            for _, eid in ipairs(imbue.wepEnchID) do
                                if
                                    eid > 0 and ((hasMH and mhEnchID == eid) or (hasOH and ohEnchID == eid))
                                then
                                    -- Uses the matched hand's expire time, not min of both -- an unenchanted hand returns 0, which would always trigger.
                                    local matchExpire
                                    if hasMH and mhEnchID == eid then
                                        matchExpire = mhExpire
                                    else
                                        matchExpire = ohExpire
                                    end
                                    if
                                        matchExpire
                                        and matchExpire > 0
                                        and IsUnderDuration(
                                            3600,
                                            matchExpire / 1000 + GetTime(),
                                            "consumable"
                                        )
                                    then
                                        found = false
                                    else
                                        found = true
                                    end
                                end
                            end
                        end
                        if not found then
                            local entry = AcquireEntry()
                            entry.mode = "spell"
                            entry.spellID = imbue.castSpell
                            entry.label =
                                ShortLabel(_G._CUABR_SpellName(imbue.castSpell, imbue.name), "SHAMAN_IMBUE")
                            entry.cat = "consumable"
                            entry.data = imbue
                            entry.dismissKey = "consumable:" .. imbue.key
                            missing[#missing + 1] = entry
                        end
                    end
                end

                -- Shaman Shields: talent-gated entries. Earth Shield self-buff (383648) is handled separately below (also OOC-only despite being whitelisted -- see that block); other shields' IDs are not whitelisted either, so they stay OOC-only.
                for _, shieldRec in ipairs(SHAMAN_SHIELDS) do
                    local castID = shieldRec.castSpellFn and shieldRec.castSpellFn() or shieldRec.castSpell
                    if collector.enabled[shieldRec.key] ~= false and Known(castID) then
                        local success = true
                        if shieldRec.requireTalent and not Known(shieldRec.requireTalent) then
                            success = false
                        end
                        if shieldRec.excludeTalent and Known(shieldRec.excludeTalent) then success = false end
                        -- es_orbit and es_ally have their own block below
                        if shieldRec.key == "es_orbit" or shieldRec.key == "es_ally" then success = false end
                        if combatNow or inKeystone then success = false end
                        if success and not PlayerHasAuraByID(shieldRec.buffIDs, "special") then
                            local entry = AcquireEntry()
                            entry.mode = "spell"
                            entry.spellID = castID
                            entry.label = ShortLabel(shieldRec.name, "SHAMAN_SHIELD")
                            entry.cat = "consumable"
                            entry.data = shieldRec
                            entry.dismissKey = "consumable:" .. shieldRec.key
                            missing[#missing + 1] = entry
                        end
                    end
                end
            end
        end -- end specialsActive

        -- === CONSUMABLES (visibility via the section "Where to Show") ===
        -- None in a PvP instance: flasks, food, runes and oils do nothing
        -- there, and their presence cannot be read; the class specials above
        -- (poisons, rites, imbues, shields) are the player's own spells and
        -- still run.
        if pvpNow then
            InkyMapWatch(false)
        else
            -- Augment Runes: presence unverifiable in combat/M+ (suppress);
            -- otherwise try the read and remind when missing.
            if
                collector.enabled.augment_rune
                and REMIND.ConsumableShows(collector, "augment_rune", instanceNow)
            then
                local hasRuneBuff = REMIND.ConsumablePresenceUnverifiable()
                    or PlayerHasAuraByID(RUNE_BUFF_IDS)
                if not hasRuneBuff then
                    local rr = REMIND._resolved.rune
                    local runeItem = rr.itemID
                    if runeItem and (collector.showWithoutItem ~= false or rr.hasBags) then
                        local entry = AcquireEntry()
                        entry.mode = "item"
                        entry.itemID = runeItem
                        entry.texture = C_Item.GetItemIconByID(runeItem)
                        entry.label = CludesUI.L(ShortLabel("Augment Rune"))
                        entry.qualityAtlas = REMIND.GetItemQualityAtlas(runeItem)
                        entry.bagCount = CachedGetItemCount(runeItem)
                        entry.desaturated = not rr.hasBags
                        entry.cat = "consumable"
                        entry.dismissKey = "consumable:rune"
                        missing[#missing + 1] = entry
                    end
                end
            end

            -- Weapon Enchants (temp enchant items; the enchant summary API is
            -- combat-safe). Skipped if the player knows any imbue spell (Shaman
            -- imbues, Paladin rites). Rogues/DKs NOT excluded -- poisons are
            -- temp enchants too, and DKs can use oils alongside runeforges.
            if
                collector.enabled.weapon_enchant
                and REMIND.ConsumableShows(collector, "weapon_enchant", instanceNow)
            then
                local _hasImbueSpell = false
                for _, spellRef in ipairs(_IMBUE_EXCLUDE_SPELLS) do
                    if IsSpellKnown(spellRef) then
                        _hasImbueSpell = true
                        break
                    end
                end
                if not _hasImbueSpell then REMIND.EmitWeaponEnchantReminders(missing, collector) end
            end

            -- Flask / Food: remind only when absence is verifiable (the checks
            -- suppress under combat/M+/restriction instead of false-firing).
            if collector.enabled.flask and REMIND.ConsumableShows(collector, "flask", instanceNow) then
                if not PlayerHasFlaskBuff() then
                    local rf = REMIND._resolved.flask
                    local flaskItemID = rf.itemID
                    if flaskItemID and (collector.showWithoutItem ~= false or rf.hasBags) then
                        local entry = AcquireEntry()
                        entry.mode = "item"
                        entry.itemID = flaskItemID
                        entry.texture = C_Item.GetItemIconByID(flaskItemID) or 134830
                        entry.label = CludesUI.L("Flask")
                        entry.qualityAtlas = REMIND.GetItemQualityAtlas(flaskItemID)
                        entry.bagCount = CachedGetItemCount(flaskItemID)
                        entry.desaturated = not rf.hasBags
                        entry.cat = "consumable"
                        entry.dismissKey = "consumable:flask"
                        missing[#missing + 1] = entry
                    end
                end
            end

            if collector.enabled.food and REMIND.ConsumableShows(collector, "food", instanceNow) then
                if not PlayerHasWellFed() then
                    local foodItemID = REMIND._resolved.food.itemID
                    if
                        foodItemID and (collector.showWithoutItem ~= false or REMIND._resolved.food.hasBags)
                    then
                        local entry = AcquireEntry()
                        entry.mode = "item"
                        entry.itemID = foodItemID
                        entry.texture = C_Item.GetItemIconByID(foodItemID) or 134062
                        entry.label = CludesUI.L("Food")
                        entry.qualityAtlas = REMIND.GetItemQualityAtlas(foodItemID)
                        entry.bagCount = CachedGetItemCount(foodItemID)
                        entry.desaturated = not REMIND._resolved.food.hasBags
                        entry.substitute = REMIND._resolved.food.isSubstitute
                        entry.cat = "consumable"
                        entry.dismissKey = "consumable:food"
                        if REMIND.IsPlayerEating() then
                            entry.isEating = true
                            entry.eatingExpirationTime = REMIND.GetEatingExpirationTime()
                        end
                        missing[#missing + 1] = entry
                    end
                end
            end

            -- Inky Black Potion (zone-specific)
            local inkyWatch = false
            if
                collector.enabled.inky_black and REMIND.ConsumableShows(collector, "inky_black", instanceNow)
            then
                local zones = collector.inkyBlackZones or ""
                if zones ~= "" then
                    inkyWatch = true
                    -- Cache parsed zone set on the string itself
                    if not collector._inkyZoneSet or collector._inkyZoneSrc ~= zones then
                        local cfg = {}
                        for zid in zones:gmatch("[^,%s]+") do
                            cfg[zid] = true
                        end
                        collector._inkyZoneSet = cfg
                        collector._inkyZoneSrc = zones
                    end
                    InkyMapWatch(true)
                    inkyIndex.set = collector._inkyZoneSet
                    inkyIndex.inZone = collector._inkyZoneSet[inkyIndex.key] or false
                    if inkyIndex.inZone then
                        local hasPotion = REMIND._resolved.inky.hasPotion
                        if not PlayerHasInkyBlackness() and hasPotion then
                            local entry = AcquireEntry()
                            entry.mode = "item"
                            entry.itemID = INKY_BLACK_ITEM
                            entry.texture = C_Item.GetItemIconByID(INKY_BLACK_ITEM)
                            entry.label = CludesUI.L(ShortLabel("Inky Black Potion"))
                            entry.qualityAtlas = REMIND.GetItemQualityAtlas(INKY_BLACK_ITEM)
                            entry.bagCount = CachedGetItemCount(INKY_BLACK_ITEM)
                            entry.cat = "consumable"
                            entry.dismissKey = "consumable:inky_black"
                            missing[#missing + 1] = entry
                        end
                    end
                end
            end
            if not inkyWatch then InkyMapWatch(false) end
        end -- not inPvP
    end -- consumables block

    -- Earth Shield self-buff (383648), only with Elemental Orbit. NOT
    -- actually combat-safe despite being whitelisted in NON_SECRET_SPELL_IDS:
    -- confirmed in-game that GetPlayerAuraBySpellID(383648) returns nothing
    -- readable in combat even while the buff is genuinely active, so a
    -- reminder already up when combat starts would get stuck (neither the
    -- live read nor the pre-combat snapshot can clear it) until combat ends.
    -- Suppress in combat/keystone instead, same as its ls_ws_orbit/
    -- shield_basic siblings just above.
    if specialsActive and classFile == "SHAMAN" then
        local esOrbit = SHAMAN_SHIELDS[1] -- es_orbit entry
        if
            collector.enabled[esOrbit.key] ~= false
            and Known(esOrbit.castSpell)
            and esOrbit.requireTalent
            and Known(esOrbit.requireTalent)
        then
            if not (combatNow or inKeystone) and not PlayerHasAuraByID(esOrbit.buffIDs) then
                local entry = AcquireEntry()
                entry.mode = "spell"
                entry.spellID = esOrbit.castSpell
                entry.label = ShortLabel(esOrbit.name, "SHAMAN_SHIELD")
                entry.cat = "consumable"
                entry.data = esOrbit
                entry.dismissKey = "consumable:" .. esOrbit.key
                missing[#missing + 1] = entry
            end
        end
        -- Our Earth Shield on a group member (es_ally, opt-in): grouped and
        -- out of combat/keystone like the self shield. The tracker cache is nil
        -- (unknown) until a lookup proves a miss; nobody in reach = no reminder.
        -- Display-only: a click would self-cast, never reaching an ally.
        local esAlly = SHAMAN_SHIELDS[2] -- es_ally entry
        if
            collector.enabled[esAlly.key] == true
            and not (combatNow or inKeystone)
            and (IsInGroup() or IsInRaid())
            and (REMIND._ownOtherAuraCache[974] == false or REMIND.OwnOtherAuraNeedsRebuff(974, "special"))
            and REMIND.AnyReachableGroupMember()
        then
            local entry = AcquireEntry()
            entry.mode = "texture"
            entry.texture = Tex(esAlly.castSpell)
            entry.spellID = esAlly.castSpell -- tooltip only
            entry.label = CludesUI.L(ShortLabel(esAlly.name))
            entry.cat = "consumable"
            entry.data = esAlly
            entry.dismissKey = "consumable:" .. esAlly.key
            missing[#missing + 1] = entry
        end
    end

    ---------------------------------------------------------------------------
    --  Healthstone in bags (group; "Where to Show" governs visibility). Bag
    --  state and class scans are combat-safe; secret class tokens skip units.
    --  In combat only the warlock is reminded: a non-warlock can't be handed
    --  a stone mid-fight, so for everyone else it is noise until the fight
    --  ends (the list rebuilds on both combat transitions).
    ---------------------------------------------------------------------------
    if
        (IsInGroup() or IsInRaid())
        and REMIND.ConsumableShows(collector, "healthstone", instanceNow)
        and not (InCombat() and GetPlayerClass() ~= "WARLOCK")
    then
        if collector and collector.enabled and collector.enabled.healthstone ~= false then
            -- Only remind if a Warlock is in the group
            local hasWarlock = false
            if IsInRaid() then
                for index = 1, GetNumGroupMembers() do
                    local _, classTok = UnitClass("raid" .. index)
                    if classTok ~= nil and not isSecret(classTok) and classTok == "WARLOCK" then
                        hasWarlock = true
                        break
                    end
                end
            else
                if GetPlayerClass() == "WARLOCK" then
                    hasWarlock = true
                else
                    for index = 1, GetNumSubgroupMembers() do
                        local _, classTok = UnitClass("party" .. index)
                        if classTok ~= nil and not isSecret(classTok) and classTok == "WARLOCK" then
                            hasWarlock = true
                            break
                        end
                    end
                end
            end
            local hasHealthstone = REMIND._resolved.healthstone.hasStone
            if hasWarlock and not hasHealthstone then
                local entry = AcquireEntry()
                entry.mode = "texture"
                entry.texture = 538745
                entry.label = CludesUI.L("HS")
                entry.cat = "consumable"
                entry.dismissKey = "consumable:healthstone"
                if saved.profile.raidBuffs.requestOnClick and GetPlayerClass() ~= "WARLOCK" then
                    entry.requestKey = "healthstone"
                    entry.requestName = CludesUI.L("Healthstones")
                end
                missing[#missing + 1] = entry
            end
        end
    end

    ---------------------------------------------------------------------------
    --  Partnered Trinket: Emerald Coach's Whistle (combat-safe via snapshot)
    ---------------------------------------------------------------------------
    do
        local co2 = saved.profile.consumables
        if
            co2
            and co2.enabled
            and co2.enabled.coaches_whistle ~= false
            and REMIND.ConsumableShows(co2, "coaches_whistle", instanceNow)
            and REMIND._cachedDiffID ~= 208
            and (IsInGroup() or IsInRaid())
            and (GetInventoryItemID("player", 13) == 193718 or GetInventoryItemID("player", 14) == 193718)
        then
            local hasBuff = PlayerHasAuraByID(PARTNERED_TRINKET.buffIDs)
            if not hasBuff then
                local entry = AcquireEntry()
                entry.mode = "texture"
                entry.texture = PARTNERED_TRINKET.icon
                entry.label = CludesUI.L("Whistle")
                entry.cat = "consumable"
                entry.dismissKey = "consumable:coaches_whistle"
                missing[#missing + 1] = entry
            end
        end
    end

    ---------------------------------------------------------------------------
    --  DK Runeforging (OOC only, check permanent enchant via item link)
    ---------------------------------------------------------------------------
    if not combatNow and classFile == "DEATHKNIGHT" then
        local co3 = saved.profile.consumables
        if co3 and co3.enabled and co3.enabled.runeforge ~= false then
            local needsRune = false
            for index = 1, 2 do
                local slot = (index == 1) and 16 or 17
                local itemLink = GetInventoryItemLink("player", slot)
                if itemLink then
                    local ench = itemLink:match("item:%d+:(-?%d+):")
                    local enchID = tonumber(ench) or 0
                    if enchID == 0 then
                        needsRune = true
                        break
                    end
                end
            end
            if needsRune then
                local entry = AcquireEntry()
                entry.mode = "texture"
                entry.texture = 135957
                entry.label = CludesUI.L("Rune")
                entry.cat = "consumable"
                entry.dismissKey = "consumable:runeforge"
                missing[#missing + 1] = entry
            end
        end
    end
end

-- CollectTalentReminders moved to CludesUIABR_TalentReminders.lua

Inner.CollectAuras, Inner.CollectConsumables = CollectAuras, CollectConsumables
Inner.CollectRaidBuffs, Inner.HideAllIcons, Inner.InkyMapWatch = CollectRaidBuffs, HideAllIcons, InkyMapWatch
Inner.LayoutIcons = LayoutIcons
Inner.ResizeAnchorCentered, Inner.ShowIcon = ResizeAnchorCentered, ShowIcon
Inner.broken = false
