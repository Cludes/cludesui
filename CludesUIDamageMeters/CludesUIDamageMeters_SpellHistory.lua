if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIDamageMeters_SpellHistory.lua
--  Standalone spell history tracker.  Two independent display modes:
--    - Icon strip: horizontal/vertical row of spell icons (grows configurable)
--    - Bar window: standalone window matching DM bar styling
--  Zero overhead when both features are disabled (no events registered).
-------------------------------------------------------------------------------
local _, mod = ...
local CUI = CludesUI

-------------------------------------------------------------------------------
--  Constants
-------------------------------------------------------------------------------
local MAX_HISTORY = 80
local BAR_TEX = "Interface\\Buttons\\WHITE8X8"
local ICON_POOL_SIZE = 40
local BAR_POOL_SIZE = 40

-- Interrupted/failed bar color (hardcoded)
local CLR_STOPPED = { 0.859, 0.255, 0.255 } -- #DB4141

local OUTCOME_TEXT = {
    failed = "|cffdb4141Failed|r",
    interrupted = "|cffdb4141Interrupted|r",
}

-------------------------------------------------------------------------------
--  DB defaults
-------------------------------------------------------------------------------
local SH_DEFAULTS = {
    iconEnabled = false,
    barEnabled = false,
    growDirection = "LEFT",
    iconSize = 36,
    iconZoom = 0.08,
    iconFadeTime = 0,
    iconSpacing = 1,
    iconCount = 5,
    iconOpacity = 1,
    iconAnimation = "none", -- none, slide, fly
    maxBars = 5,
    hideTopBar = false,
    barWidth = 300,
    barLocked = false,
    barPos = nil,
    iconPos = nil,
    barColorUseClass = false,
    barColorUseAccent = false,
    barColor = { r = 0.298, g = 0.565, b = 0.494 }, -- #4C907E
    barOpacity = 1,
    spellHistoryBarTexture = "match",
    textSize = 11,
    textColorUseAccent = false,
    textColor = { r = 1, g = 1, b = 1 },
    shBarHeight = 20,
    bgR = 0,
    bgG = 0,
    bgB = 0,
    bgAlpha = 0.25,
    iconHideInDungeon = false,
    iconHideInRaid = false,
    iconHideInDelve = false,
    iconHideInPvP = false,
    iconHideOutOfInstance = false,
    barHideInDungeon = false,
    barHideInRaid = false,
    barHideInDelve = false,
    barHideInPvP = false,
    barHideOutOfInstance = false,
}

-------------------------------------------------------------------------------
--  Shared history buffer (newest at index 1)
-------------------------------------------------------------------------------
local _history = {}
local _pendingCasts = {}

-------------------------------------------------------------------------------
--  Helpers
-------------------------------------------------------------------------------
local floor, format, min, upper = math.floor, string.format, math.min, math.max
local GetTime = GetTime

-- Spell info cache: spellID -> { name, iconID } (never changes for a given ID)
local _spellInfoCache = {}

-- Cached DB accessor; defaults are merged once at init, not per-call
local _shDB
local function SavedDB()
    if _shDB then
        return _shDB
    end
    local d = mod.EDM.DB()
    if not d.spellHistory then
        d.spellHistory = {}
    end
    local sh = d.spellHistory
    for k, v in pairs(SH_DEFAULTS) do
        if sh[k] == nil then
            sh[k] = v
        end
    end
    _shDB = sh
    return sh
end

local function SetFont(fontStr, dim)
    CludesUI.ApplyModuleFont(fontStr, nil, dim, "damageMeters")
end

-- Icon size is a coordinate value like the window width and icon spacing, so it
-- keeps its proportion at any UI scale; only snapped onto the pixel grid.
local function SnapSize(val)
    local Pix = CUI and CUI.PP
    if Pix and Pix.Snap then
        return Pix.Snap(val or 0)
    end
    return val or 0
end

local function GetBarTexturePath()
    local dmCfg = mod.EDM.DB()
    local sh = SavedDB()
    local key = sh.spellHistoryBarTexture
    if not key or key == "match" then
        key = (dmCfg and dmCfg.barTexture) or "none"
    end
    local texTable = _G._CUDM_BarTextures
    if texTable then
        return CUI.ResolveTexturePath(texTable, key, BAR_TEX)
    end
    return BAR_TEX
end

local function GetAccentRGB()
    local ACC = CUI.CLUDES_GREEN
    if ACC then
        return ACC.r, ACC.g, ACC.b
    end
    return CUI.DEFAULT_ACCENT_R or 76 / 255,
        CUI.DEFAULT_ACCENT_G or 201 / 255,
        CUI.DEFAULT_ACCENT_B or 240 / 255
end

local function OutcomeColor(status)
    if status == "failed" or status == "interrupted" then
        return CLR_STOPPED[1], CLR_STOPPED[2], CLR_STOPPED[3]
    end
    local sh = SavedDB()
    if sh.barColorUseClass then
        local _, classFile = UnitClass("player")
        local cc = classFile
            and RAID_CLASS_COLORS
            and RAID_CLASS_COLORS[classFile]
            and CUI.GetClassColor(classFile)
        if cc then
            return cc.r, cc.g, cc.b
        end
    end
    if sh.barColorUseAccent then
        return GetAccentRGB()
    end
    local c = sh.barColor
    return c and c.r or 0.298, c and c.g or 0.565, c and c.b or 0.494
end

-- Resolve spell override (base -> active override) for correct name/icon
local function ResolveOverride(spellRef)
    if C_Spell and C_Spell.GetOverrideSpell then
        local shade = C_Spell.GetOverrideSpell(spellRef)
        if shade and shade ~= 0 and shade ~= spellRef then
            return shade
        end
    end
    if FindSpellOverrideByID then
        local shade = FindSpellOverrideByID(spellRef)
        if shade and shade ~= 0 and shade ~= spellRef then
            return shade
        end
    end
    return spellRef
end

local function FormatCastTime(record)
    if record.isInstant then
        return ""
    end
    local status = record.status
    -- Active cast: show elapsed time counting up
    if status == "casting" or status == "channeling" then
        local elapsed = GetTime() - record.startTime
        if elapsed > 0 then
            return format("%.1f", elapsed)
        end
        return ""
    end
    -- Completed/failed: show total duration
    if record.castDuration and record.castDuration > 0 then
        return format("%.1fs", record.castDuration)
    end
    return ""
end

-- Build right-side text without allocating a temp table each time
local function BuildRightText(record)
    local castStr = FormatCastTime(record)
    local outcomeStr = OUTCOME_TEXT[record.status]
    -- Outcome (Interrupted/Failed) replaces target; otherwise show target.
    -- Enemy names in M+ are secret values but FontStrings can display them.
    local targetUnit = record.target
    local isSecret = targetUnit and issecretvalue and issecretvalue(targetUnit)
    local hasTarget = targetUnit and (isSecret or targetUnit ~= "")
    -- Strip realm suffix for non-secret names (secret values pass through to FontString as-is)
    if hasTarget and not isSecret and not outcomeStr and Ambiguate then
        targetUnit = Ambiguate(targetUnit, "short")
    end
    local rightPart = outcomeStr or (hasTarget and targetUnit) or nil
    local result
    if castStr ~= "" and rightPart then
        result = castStr .. "  " .. rightPart
    elseif castStr ~= "" then
        result = castStr
    elseif rightPart then
        result = rightPart
    else
        result = ""
    end
    return result
end

-------------------------------------------------------------------------------
--  Forward declarations (defined after UI code)
-------------------------------------------------------------------------------
local RefreshBarWindow
local BuildIconStrip
local StartCastAnim

-------------------------------------------------------------------------------
--  History management
-------------------------------------------------------------------------------
local function RefreshViews()
    local sh = SavedDB()
    if sh.iconEnabled then
        BuildIconStrip()
    end
    if sh.barEnabled then
        RefreshBarWindow()
    end
end

local function PushEntry(record)
    table.insert(_history, 1, record)
    if #_history > MAX_HISTORY then
        _history[#_history] = nil
    end
    RefreshViews()
end

local _pendingTargets = {} -- castGUID -> target name (from UNIT_SPELLCAST_SENT)
local _activeChannelSpell = nil -- spellID of currently channeling spell (suppress tick SUCCEEDEDs)
local _knownOverrides = {} -- spellID -> true for override spells that pass IsSpellKnownOrOverridesKnown

-- Healthstones and potions cast spells outside the spellbook, so the known-spell
-- filter lets exactly their cast ids through: the ids the shared consumables
-- catalogue lists (CludesUI.CONSUMABLES) plus each of its items' use spell.
-- Each id maps to the item whose icon its entry shows (a use spell's own icon
-- is often a generic one). An item the client has not cached yet adds its
-- spell once its data arrives, through a listener held only while one is
-- pending. Built when tracking first turns on.
local _consumableSpells = {}
local BuildConsumableSpells
do
    local built, pending, loader = false, {}, nil
    local function AddUseSpell(itemId)
        local _, spellRef = C_Item.GetItemSpell(itemId)
        if spellRef and not _consumableSpells[spellRef] then
            _consumableSpells[spellRef] = itemId
        end
    end
    local function AddItem(itemId)
        if C_Item.IsItemDataCachedByID(itemId) then
            AddUseSpell(itemId)
        else
            pending[itemId] = true
        end
    end
    BuildConsumableSpells = function()
        if built then
            return
        end
        built = true
        -- WoW Forever offers only the Healthstone family, with that client's stones.
        local fv = CUI.IS_FOREVER == true
        for key, fam in pairs(CUI.CONSUMABLES) do
            if not fv or key == "healthstone" then
                local ids = fam.spellIDs
                if ids then
                    for i = 1, #ids do
                        _consumableSpells[ids[i]] = fam.itemID
                    end
                end
                AddItem(fam.itemID)
                local alts = fv and CUI.FOREVER_HEALTHSTONES or fam.altItemIDs
                if alts then
                    for i = 1, #alts do
                        AddItem(alts[i])
                    end
                end
            end
        end
        if not next(pending) then
            return
        end
        loader = CreateFrame("Frame")
        loader:SetScript("OnEvent", function(self, _, itemId, success)
            if not pending[itemId] then
                return
            end
            pending[itemId] = nil
            if success then
                AddUseSpell(itemId)
            end
            if not next(pending) then
                self:UnregisterAllEvents()
            end
        end)
        loader:RegisterEvent("ITEM_DATA_LOAD_RESULT")
        for itemId in pairs(pending) do
            C_Item.RequestLoadItemDataByID(itemId)
        end
    end
end

-- An entry's icon: a consumable's item icon, else the spell's.
local function EntryIcon(spellId, details)
    local itemId = spellId and _consumableSpells[spellId]
    return itemId and C_Item.GetItemIconByID(itemId) or (details and details.iconID)
end

-- The castGUID of the consumable use the player last sent (UNIT_SPELLCAST_SENT).
-- One use can report a second cast, an effect it triggers, which is never
-- sent: a consumable cast not sent right after a consumable entry is that
-- same use, so it adds no entry.
local _sentConsumable = nil

local function FinishPending(castGUID, status)
    _pendingTargets[castGUID] = nil
    local record = _pendingCasts[castGUID]
    if not record then
        return
    end
    -- Don't downgrade a success (server accepted) to failed/interrupted (client race)
    if record.status == "success" then
        _pendingCasts[castGUID] = nil
        return
    end
    -- Snapshot fill progress for interrupted/failed casts so the bar freezes
    if status == "interrupted" or status == "failed" then
        local nowTime = GetTime()
        local dur = record.endTime - record.startTime
        if dur > 0 then
            if record.isChannel then
                record.fillProgress = upper(0, min(1, (record.endTime - nowTime) / dur))
            else
                record.fillProgress = upper(0, min(1, (nowTime - record.startTime) / dur))
            end
        end
    end
    record.status = status
    record.endTime = GetTime()
    if record.startTime then
        record.castDuration = record.endTime - record.startTime
    end
    _pendingCasts[castGUID] = nil
    RefreshViews()
end

-------------------------------------------------------------------------------
--  Event-driven spell tracking
--  Events are only registered when at least one feature is enabled.
-------------------------------------------------------------------------------
local _eventsActive = false
local eventFrame = CreateFrame("Frame")

local function OnSpellEvent(_, evt, unitToken, ...)
    if unitToken ~= "player" then
        return
    end

    -- UNIT_SPELLCAST_SENT has unique args: unit, target, castGUID, spellID
    if evt == "UNIT_SPELLCAST_SENT" then
        local targetUnit, castGUID2, sentSpellID = ...
        if castGUID2 and targetUnit then
            _pendingTargets[castGUID2] = targetUnit
        end
        if castGUID2 and sentSpellID and _consumableSpells[sentSpellID] then
            _sentConsumable = castGUID2
        end
        return
    end

    local castGUID, spellId = ...

    if evt == "UNIT_SPELLCAST_START" then
        local name, _, _, startMS, endMS = UnitCastingInfo("player")
        if not name or not spellId then
            return
        end
        spellId = ResolveOverride(spellId)
        local details = _spellInfoCache[spellId]
        if not details then
            details = C_Spell and C_Spell.GetSpellInfo(spellId)
            if details then
                _spellInfoCache[spellId] = details
            end
        end
        local record = {
            spellID = spellId,
            spellName = name,
            icon = EntryIcon(spellId, details),
            target = castGUID and _pendingTargets[castGUID],
            startTime = (startMS or 0) / 1000,
            endTime = (endMS or 0) / 1000,
            castDuration = ((endMS or 0) - (startMS or 0)) / 1000,
            status = "casting",
            isInstant = false,
            isChannel = false,
            consumable = _consumableSpells[spellId] and true or nil,
            timestamp = GetTime(),
        }
        if castGUID then
            _pendingCasts[castGUID] = record
        end
        PushEntry(record)
        StartCastAnim()
    elseif evt == "UNIT_SPELLCAST_CHANNEL_START" then
        local name, _, _, startMS, endMS, _, _, chanSpellID = UnitChannelInfo("player")
        local spellRef = ResolveOverride(chanSpellID or spellId)
        if not name then
            return
        end
        local details = spellRef and _spellInfoCache[spellRef]
        if not details and spellRef then
            details = C_Spell and C_Spell.GetSpellInfo(spellRef)
            if details then
                _spellInfoCache[spellRef] = details
            end
        end
        local record = {
            spellID = spellRef,
            spellName = name,
            icon = EntryIcon(spellRef, details),
            target = castGUID and _pendingTargets[castGUID],
            startTime = (startMS or 0) / 1000,
            endTime = (endMS or 0) / 1000,
            castDuration = ((endMS or 0) - (startMS or 0)) / 1000,
            status = "channeling",
            isInstant = false,
            isChannel = true,
            consumable = spellRef and _consumableSpells[spellRef] and true or nil,
            timestamp = GetTime(),
        }
        _activeChannelSpell = spellRef
        if castGUID then
            _pendingCasts[castGUID] = record
        end
        PushEntry(record)
        StartCastAnim()
    elseif evt == "UNIT_SPELLCAST_SUCCEEDED" then
        if castGUID and _pendingCasts[castGUID] then
            FinishPending(castGUID, "success")
        else
            -- Skip channeled spell ticks (SUCCEEDED fires per tick during a channel)
            if _activeChannelSpell and spellId == _activeChannelSpell then
                return
            end
            -- Skip internal/system spells (LOGINEFFECT, DNT, etc.)
            -- IsPlayerSpell catches most, but override/transform spells (e.g.
            -- Lightsmith armaments) fail it. Fall back to IsSpellKnownOrOverridesKnown
            -- and cache the result (that API is flaky on repeated calls).
            -- Healthstones and potions pass through the consumables set.
            local consumable = _consumableSpells[spellId] and true or nil
            if not IsPlayerSpell(spellId) then
                if not _knownOverrides[spellId] then
                    if IsSpellKnownOrOverridesKnown and IsSpellKnownOrOverridesKnown(spellId) then
                        _knownOverrides[spellId] = true
                    elseif not consumable then
                        return
                    end
                end
            end
            if consumable then
                if castGUID and castGUID == _sentConsumable then
                    _sentConsumable = nil
                elseif _history[1] and _history[1].consumable then
                    return
                end
            end
            spellId = ResolveOverride(spellId)
            -- Latency race: INTERRUPTED/FAILED can fire before SUCCEEDED at
            -- the end of a cast.  The pending entry is already consumed and
            -- sitting in _history with a wrong status.  Scan recent history
            -- and fix it instead of creating a duplicate.
            local dominated = false
            -- Check pending casts first (different/nil castGUID race)
            for groupId, pe in pairs(_pendingCasts) do
                if pe.spellID == spellId then
                    FinishPending(groupId, "success")
                    dominated = true
                    break
                end
            end
            -- Check recent history (INTERRUPTED already consumed the entry)
            if not dominated then
                for hi = 1, min(#_history, 5) do
                    local he = _history[hi]
                    if he.spellID == spellId and (he.status == "interrupted" or he.status == "failed") then
                        he.status = "success"
                        he.fillProgress = nil
                        dominated = true
                        RefreshViews()
                        break
                    end
                end
            end
            if not dominated then
                local details = spellId and _spellInfoCache[spellId]
                if not details and spellId then
                    details = C_Spell and C_Spell.GetSpellInfo(spellId)
                    if details then
                        _spellInfoCache[spellId] = details
                    end
                end
                if not details then
                    return
                end
                PushEntry({
                    spellID = spellId,
                    spellName = details.name or "?",
                    icon = EntryIcon(spellId, details),
                    target = castGUID and _pendingTargets[castGUID],
                    startTime = GetTime(),
                    endTime = GetTime(),
                    castDuration = 0,
                    status = "success",
                    isInstant = true,
                    isChannel = false,
                    consumable = consumable,
                    timestamp = GetTime(),
                })
            end
        end
    elseif evt == "UNIT_SPELLCAST_FAILED" or evt == "UNIT_SPELLCAST_FAILED_QUIET" then
        if castGUID then
            FinishPending(castGUID, "failed")
        end
    elseif evt == "UNIT_SPELLCAST_INTERRUPTED" then
        if castGUID then
            FinishPending(castGUID, "interrupted")
        end
    elseif evt == "UNIT_SPELLCAST_STOP" then
        if not castGUID then
            return
        end
        local record = _pendingCasts[castGUID]
        if record and record.status == "casting" then
            local groupId = castGUID
            C_Timer.After(0, function()
                if _pendingCasts[groupId] and _pendingCasts[groupId].status == "casting" then
                    FinishPending(groupId, "failed")
                end
            end)
        end
    elseif evt == "UNIT_SPELLCAST_CHANNEL_STOP" then
        _activeChannelSpell = nil
        if castGUID then
            _pendingTargets[castGUID] = nil
            local record = _pendingCasts[castGUID]
            if record then
                if record.status == "channeling" then
                    record.status = "success"
                end
                record.endTime = GetTime()
                if record.startTime then
                    record.castDuration = record.endTime - record.startTime
                end
                _pendingCasts[castGUID] = nil
            end
        end
    end
end

local function RegisterEvents()
    if _eventsActive then
        return
    end
    BuildConsumableSpells()
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player") -- player only (was global, fired for all units)
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    eventFrame:SetScript("OnEvent", OnSpellEvent)
    _eventsActive = true
end

local function UnregisterEvents()
    if not _eventsActive then
        return
    end
    eventFrame:UnregisterAllEvents()
    eventFrame:SetScript("OnEvent", nil)
    _eventsActive = false
end

-------------------------------------------------------------------------------
--  Instance visibility check
-------------------------------------------------------------------------------
local function ShouldHide(hideInDungeon, hideInRaid, hideInDelve, hideInPvP, hideOutOfInstance)
    -- Always visible while configuring or positioning the element.
    if mod._optionsOpen or CUI._unlockActive then
        return false
    end
    -- Show/hide all windows hotkey. Both displays rebuild themselves on every cast, so
    -- the check belongs here rather than in a one-off hide from ns.ApplyDMToggleState.
    if mod._toggleHidden and mod.EDM.DB().toggleIncludeSpellHistory then
        return true
    end
    local _, iType = IsInInstance()
    if hideInDungeon and iType == "party" then
        return true
    end
    if hideInRaid and iType == "raid" then
        return true
    end
    if hideInDelve and CUI.IsInDelve() then
        return true
    end
    if hideInPvP and (iType == "pvp" or iType == "arena") then
        return true
    end
    if hideOutOfInstance and (iType == "none" or iType == nil) then
        return true
    end
    return false
end

-------------------------------------------------------------------------------
--  ICON STRIP  (standalone movable frame)
-------------------------------------------------------------------------------
local _iconContainer
local _iconStrip
local _iconPool = {}
local _lastAnimTimestamp = 0 -- tracks when to animate icon 1
local _lastIconCount = 0 -- tracks visible count for minimal loop
local _iconLayoutKey = "" -- tracks settings that affect icon layout (skip repositioning if unchanged)

local ANIM_DUR = 0.5
local ANIM_SLIDE_PX = 6

-- The saved iconPos remains the TOPLEFT of the newest icon, matching every
-- existing profile.  The container expands around that fixed icon so changing
-- the history length or growth direction never makes the row wander.
local function IconStripGeometry(count)
    local sh = SavedDB()
    local iconSz = SnapSize(sh.iconSize or 24)
    local gap = sh.iconSpacing or 1
    local dir = sh.growDirection or "LEFT"
    count = upper(1, count or sh.iconCount or 5)
    local span = count * iconSz + (count - 1) * gap
    local horizontal = dir == "LEFT" or dir == "RIGHT"
    local width = horizontal and span or iconSz
    local height = horizontal and iconSz or span
    local leftOffset = dir == "LEFT" and (span - iconSz) or 0
    local upOffset = dir == "UP" and (span - iconSz) or 0
    return iconSz, gap, dir, width, height, leftOffset, upOffset
end

local function PositionIconContainer(count)
    if not _iconContainer or not _iconStrip then
        return
    end
    local iconSz, _, dir, width, height, leftOffset, upOffset = IconStripGeometry(count)

    _iconContainer:SetSize(width, height)
    _iconStrip:SetSize(iconSz, iconSz)
    _iconStrip:ClearAllPoints()
    if dir == "RIGHT" then
        _iconStrip:SetPoint("LEFT", _iconContainer, "LEFT", 0, 0)
    elseif dir == "LEFT" then
        _iconStrip:SetPoint("RIGHT", _iconContainer, "RIGHT", 0, 0)
    elseif dir == "DOWN" then
        _iconStrip:SetPoint("TOP", _iconContainer, "TOP", 0, 0)
    else
        _iconStrip:SetPoint("BOTTOM", _iconContainer, "BOTTOM", 0, 0)
    end

    -- The shared anchor system owns placement while this element is linked.
    if CUI.IsUnlockAnchored and CUI.IsUnlockAnchored("EDM_IconHistory") then
        return
    end

    local place = SavedDB().iconPos
    local firstLeft, firstTop
    if place and place.x and place.y then
        firstLeft, firstTop = place.x, place.y
    else
        firstLeft = UIParent:GetWidth() * 0.5 - iconSz * 0.5
        firstTop = UIParent:GetHeight() * 0.5 + iconSz * 0.5
    end
    _iconContainer:ClearAllPoints()
    _iconContainer:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", firstLeft - leftOffset, firstTop + upOffset)
end

local function SaveIconPositionFromFrame(count)
    if not _iconContainer then
        return
    end
    local leftX, topY = _iconContainer:GetLeft(), _iconContainer:GetTop()
    if not leftX or not topY then
        return
    end
    local _, _, _, _, _, leftOffset, upOffset = IconStripGeometry(count)
    SavedDB().iconPos = { x = leftX + leftOffset, y = topY - upOffset }
end

local function StartIconDrag(button)
    local anchored = CUI.IsUnlockAnchored and CUI.IsUnlockAnchored("EDM_IconHistory")
    if button == "LeftButton" and IsShiftKeyDown() and _iconContainer and not anchored then
        _iconContainer._dragging = true
        _iconContainer:StartMoving()
    end
end

local function StopIconDrag()
    if not _iconContainer then
        return
    end
    _iconContainer._dragging = nil
    _iconContainer:StopMovingOrSizing()
    SaveIconPositionFromFrame(_iconContainer._layoutCount)
    -- Shift may have been released during drag; disable mouse now.
    if not IsShiftKeyDown() then
        _iconStrip:EnableMouse(false)
        for _, ic in ipairs(_iconPool) do
            ic.frame:EnableMouse(false)
        end
    end
end

-------------------------------------------------------------------------------
--  Fade-out clock (iconFadeTime > 0): each icon expires individually once
--  its cast is older than the configured time, fading to zero over FADE_DUR.
--  Event-driven -- nothing runs while no icon is inside its fade window:
--    * out of combat, ONE one-shot timer is armed for the moment the next
--      icon begins fading; while an icon is actively fading, a throttled
--      OnUpdate driver (hidden when idle) repaints the strip;
--    * in combat everything is parked, so the history stays readable
--      through a fight. PLAYER_REGEN_ENABLED credits each entry the time
--      it spent in combat (per-entry base: icons cast mid-fight are
--      credited only their own in-combat lifetime) and restarts the clock.
-------------------------------------------------------------------------------
local FADE_DUR = 1.5
local _fadeTimer -- one-shot C_Timer.NewTimer for the next fade start
local _fadeDriver -- throttled OnUpdate frame, shown only while fading
local _fadeEvents -- REGEN watcher, created on first use
local _combatStart

local function FadeBase(e)
    return e._fadeBase or e.timestamp or 0
end

local function StopFadeClock()
    if _fadeTimer then
        _fadeTimer:Cancel()
        _fadeTimer = nil
    end
    if _fadeDriver then
        _fadeDriver:Hide()
    end
end

-- Arms exactly one of: the fast driver (an icon is mid-fade) or a one-shot timer for
-- the next fade start. Out-of-combat only; entries are newest first, so effective ages
-- grow with the index and the scan can stop at the first fully-faded entry.
local function ScheduleFade(fadeTime, maxIcons)
    StopFadeClock()
    local num = min(#_history, maxIcons)
    if num == 0 then
        return
    end
    local nowTime = GetTime()
    local fading = false
    local nextIn
    for i = 1, num do
        local age = nowTime - FadeBase(_history[i])
        if age < fadeTime then
            local d = fadeTime - age
            if not nextIn or d < nextIn then
                nextIn = d
            end
        elseif age < fadeTime + FADE_DUR then
            fading = true
            break
        else
            break
        end
    end
    if fading then
        if not _fadeDriver then
            _fadeDriver = CreateFrame("Frame")
            _fadeDriver:Hide()
            local acc = 0
            _fadeDriver:SetScript("OnUpdate", function(_, dt)
                acc = acc + dt
                if acc < 0.05 then
                    return
                end
                acc = 0
                BuildIconStrip()
            end)
        end
        _fadeDriver:Show()
    elseif nextIn then
        _fadeTimer = C_Timer.NewTimer(nextIn + 0.02, BuildIconStrip)
    end
end

local function EnsureFadeEvents()
    if _fadeEvents then
        return
    end
    _fadeEvents = CreateFrame("Frame")
    _fadeEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
    _fadeEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
    _fadeEvents:SetScript("OnEvent", function(_, evt)
        if evt == "PLAYER_REGEN_DISABLED" then
            _combatStart = GetTime()
            StopFadeClock()
        else
            local cs = _combatStart
            _combatStart = nil
            if (SavedDB().iconFadeTime or 0) <= 0 then
                return
            end
            local nowTime = GetTime()
            cs = cs or nowTime
            for i = 1, #_history do
                local e = _history[i]
                local baseValue = FadeBase(e)
                e._fadeBase = baseValue + (nowTime - upper(cs, baseValue))
            end
            BuildIconStrip()
        end
    end)
end

-- Plays a one-shot intro animation on an icon frame.
-- Uses dt-accumulated OnUpdate for smooth sub-frame interpolation.
-- Only called on icon 1, which always rests at CENTER of _iconStrip.
local function PlayIconAnim(ic, animType, dir, targetAlpha)
    local f = ic.frame
    targetAlpha = targetAlpha or 1

    -- Kill any in-progress animation and snap to rest position.
    -- Using hardcoded rest anchor (icon 1 = CENTER,0,0) instead of
    -- GetPoint, which returns mid-animation displacement on rapid casts.
    f:SetScript("OnUpdate", nil)
    f:SetScale(1)
    f:ClearAllPoints()
    f:SetPoint("CENTER", _iconStrip, "CENTER", 0, 0)

    local p1, rel, relP, origX, origY = "CENTER", _iconStrip, "CENTER", 0, 0

    -- Compute starting displacement for slide types
    local dx, dy = 0, 0
    if animType == "slide" then
        if dir == "LEFT" then
            dx = ANIM_SLIDE_PX
        elseif dir == "RIGHT" then
            dx = -ANIM_SLIDE_PX
        elseif dir == "UP" then
            dy = -ANIM_SLIDE_PX
        else
            dy = ANIM_SLIDE_PX
        end
    end

    local isFly = (animType == "fly")
    local elapsed = 0
    local startAlpha = targetAlpha * 0.5

    f:SetAlpha(startAlpha)
    if isFly then
        f:SetScale(1.35)
    end
    if dx ~= 0 or dy ~= 0 then
        f:SetPoint(p1, rel, relP, origX + dx, origY + dy)
    end

    f:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        local t = elapsed / ANIM_DUR
        if t >= 1 then
            t = 1
        end

        local inv = 1 - t
        local ease = 1 - inv * inv * inv

        self:SetAlpha(startAlpha + (targetAlpha - startAlpha) * ease)

        if dx ~= 0 or dy ~= 0 then
            self:SetPoint(p1, rel, relP, origX + dx * (1 - ease), origY + dy * (1 - ease))
        end

        if isFly then
            self:SetScale(1.35 + (1 - 1.35) * ease)
        end

        if t >= 1 then
            self:SetAlpha(targetAlpha)
            self:SetScript("OnUpdate", nil)
            if isFly then
                self:SetScale(1)
            end
            if dx ~= 0 or dy ~= 0 then
                self:SetPoint(p1, rel, relP, origX, origY)
            end
        end
    end)
end

local function MakeIcon(hostFrame)
    local ic = {}
    ic.frame = CreateFrame("Frame", nil, hostFrame)
    ic.frame:EnableMouse(false)
    -- Shift+drag on any icon moves the entire strip
    ic.frame:SetScript("OnMouseDown", function(_, button)
        StartIconDrag(button)
    end)
    ic.frame:SetScript("OnMouseUp", StopIconDrag)
    local backdrop = ic.frame:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(0, 0, 0, 0.4)
    ic.bg = backdrop
    ic.tex = ic.frame:CreateTexture(nil, "ARTWORK")
    ic.tex:SetAllPoints()
    local z = SavedDB().iconZoom or 0.08
    ic.tex:SetTexCoord(z, 1 - z, z, 1 - z)
    ic.frame:Hide()
    return ic
end

-- Preview icons: random spells from the player's action bars
local _previewIcons
local function GetPreviewIcons()
    if _previewIcons then
        return _previewIcons
    end
    _previewIcons = {}
    -- Pull from action bars first (most recognizable spells)
    for slotIndex = 1, 120 do
        local actionType, ident = GetActionInfo(slotIndex)
        if actionType == "spell" and ident and ident > 0 then
            local texture = GetActionTexture(slotIndex)
            if texture then
                -- Deduplicate
                local dup = false
                for _, t in ipairs(_previewIcons) do
                    if t == texture then
                        dup = true
                        break
                    end
                end
                if not dup then
                    _previewIcons[#_previewIcons + 1] = texture
                    if #_previewIcons >= 10 then
                        break
                    end
                end
            end
        end
    end
    -- Fallback if action bars returned nothing
    if #_previewIcons == 0 then
        _previewIcons = { 134400, 134400, 134400 }
    end
    return _previewIcons
end

BuildIconStrip = function()
    local sh = SavedDB()
    if
        not sh.iconEnabled
        or ShouldHide(
            sh.iconHideInDungeon,
            sh.iconHideInRaid,
            sh.iconHideInDelve,
            sh.iconHideInPvP,
            sh.iconHideOutOfInstance
        )
    then
        if _iconContainer then
            _iconContainer:Hide()
        end
        StopFadeClock()
        return
    end

    if not _iconContainer then
        _iconContainer = CreateFrame("Frame", "CludesUIDMIconHistoryFrame", UIParent)
        _iconContainer:SetFrameStrata("MEDIUM")
        _iconContainer:SetFrameLevel(10)
        _iconContainer:SetClampedToScreen(true)
        _iconContainer:SetMovable(true)
        _iconContainer:EnableMouse(false)

        _iconStrip = CreateFrame("Frame", "CludesUIDMIconStrip", _iconContainer)
        _iconStrip:SetFrameStrata("MEDIUM")
        _iconStrip:SetFrameLevel(10)
        _iconStrip:EnableMouse(false)
        _iconStrip:SetScript("OnMouseDown", function(_, button)
            StartIconDrag(button)
        end)
        _iconStrip:SetScript("OnMouseUp", StopIconDrag)
        -- Click-through unless shift is held (strip + all icon children).
        -- The Shift watch is registered only while the strip is visible; each
        -- show re-reads Shift so a press or release made while hidden is not missed.
        local modFrame = CreateFrame("Frame")
        local function SetShiftMouse(enabled)
            -- Don't disable mouse mid-drag; let OnMouseUp end it naturally
            if not enabled and _iconContainer._dragging then
                return
            end
            _iconStrip:EnableMouse(enabled)
            for _, ic in ipairs(_iconPool) do
                ic.frame:EnableMouse(enabled)
            end
        end
        modFrame:SetScript("OnEvent", function(_, _, key, down)
            if key == "LSHIFT" or key == "RSHIFT" then
                SetShiftMouse(down == 1)
            end
        end)
        _iconContainer:SetScript("OnShow", function()
            modFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
            SetShiftMouse(IsShiftKeyDown() and true or false)
        end)
        _iconContainer:SetScript("OnHide", function()
            modFrame:UnregisterEvent("MODIFIER_STATE_CHANGED")
        end)
        -- Starts hidden so the first Show below runs the OnShow registration.
        _iconContainer:Hide()
        -- Per-icon backgrounds (created in MakeIcon) travel with each icon
        -- during animation. No strip-level background needed.
    end

    local iconSz = SnapSize(sh.iconSize or 24)
    local gap = sh.iconSpacing or 1
    local dir = sh.growDirection or "LEFT"
    local iconZoom = sh.iconZoom or 0.08

    local maxIcons = sh.iconCount or 5
    local histCount = min(#_history, maxIcons)

    -- Fade-out: out of combat, entries past fadeTime+FADE_DUR drop off the
    -- strip (newest first, so the scan stops at the first faded one) and the
    -- clock re-arms for whatever comes next. In combat nothing runs; the
    -- REGEN watcher restarts the clock. fadeNow doubles as the "fade math
    -- active" flag for the alpha pass in the icon loop below.
    local fadeTime = sh.iconFadeTime or 0
    local fadeNow
    if fadeTime > 0 then
        EnsureFadeEvents()
        if not InCombatLockdown() then
            fadeNow = GetTime()
            if histCount > 0 then
                local visible = 0
                for i = 1, histCount do
                    if fadeNow - FadeBase(_history[i]) < fadeTime + FADE_DUR then
                        visible = i
                    else
                        break
                    end
                end
                histCount = visible
            end
            ScheduleFade(fadeTime, maxIcons)
        end
    else
        StopFadeClock()
    end

    -- Unlock Mode always reserves the configured maximum footprint. Live
    -- history and fade state may change the icon contents, but never the mover
    -- size while the user is positioning it. The options preview keeps its
    -- existing behavior and does not backfill slots vacated by faded icons.
    local showPreview = CUI._unlockActive
        or (mod._optionsOpen and histCount < maxIcons and not (fadeTime > 0 and #_history > 0))
    local count = showPreview and maxIcons or histCount

    -- Nothing to show: hide the strip entirely
    if count == 0 then
        _iconContainer:Hide()
        return
    end

    -- Position and size only on layout change (checked after count is known)
    local iconAlphaCheck = sh.iconOpacity or 1
    local needsLayout = (iconSz .. "|" .. gap .. "|" .. dir .. "|" .. count .. "|" .. iconAlphaCheck)
        ~= _iconLayoutKey
    if needsLayout then
        _iconContainer._layoutCount = count
        PositionIconContainer(count)
    end

    while #_iconPool < ICON_POOL_SIZE do
        _iconPool[#_iconPool + 1] = MakeIcon(_iconStrip)
    end

    -- Layout only changes when settings change; content changes every cast.
    local iconAlpha = iconAlphaCheck
    local layoutChanged = needsLayout
    local loopEnd = upper(count, _lastIconCount or 0)

    for i = 1, loopEnd do
        local ic = _iconPool[i]
        if not ic then
            break
        end
        if i <= count then
            if ic._cachedZoom ~= iconZoom then
                ic._cachedZoom = iconZoom
                ic.tex:SetTexCoord(iconZoom, 1 - iconZoom, iconZoom, 1 - iconZoom)
            end
            if layoutChanged then
                ic.frame:SetScript("OnUpdate", nil)
                ic.frame:SetScale(1)
                ic.frame:SetSize(iconSz, iconSz)
                ic.frame:ClearAllPoints()
                local offset = (i - 1) * (iconSz + gap)
                if i == 1 then
                    ic.frame:SetPoint("CENTER", _iconStrip, "CENTER", 0, 0)
                elseif dir == "RIGHT" then
                    ic.frame:SetPoint("CENTER", _iconStrip, "CENTER", offset, 0)
                elseif dir == "LEFT" then
                    ic.frame:SetPoint("CENTER", _iconStrip, "CENTER", -offset, 0)
                elseif dir == "DOWN" then
                    ic.frame:SetPoint("CENTER", _iconStrip, "CENTER", 0, -offset)
                else
                    ic.frame:SetPoint("CENTER", _iconStrip, "CENTER", 0, offset)
                end
                ic.frame:SetAlpha(iconAlpha)
                ic.frame:Show()
            end

            if i <= histCount then
                local record = _history[i]
                -- Only update texture/color when entry changes
                if ic._cachedEntry ~= record then
                    ic._cachedEntry = record
                    if record.icon then
                        ic.tex:SetTexture(record.icon)
                    end
                    ic._cachedStatus = nil
                end
                local st = record.status
                if ic._cachedStatus ~= st then
                    ic._cachedStatus = st
                    if st == "failed" or st == "interrupted" then
                        ic.tex:SetVertexColor(CLR_STOPPED[1], CLR_STOPPED[2], CLR_STOPPED[3], 1)
                    else
                        ic.tex:SetVertexColor(1, 1, 1, 1)
                    end
                    ic.tex:SetAlpha(1)
                end
                if fadeNow then
                    local age = fadeNow - FadeBase(record)
                    if age > fadeTime then
                        local k = 1 - (age - fadeTime) / FADE_DUR
                        if k < 0 then
                            k = 0
                        end
                        ic.frame:SetAlpha(iconAlpha * k)
                        ic._fading = true
                    elseif ic._fading then
                        ic.frame:SetAlpha(iconAlpha)
                        ic._fading = nil
                    end
                elseif ic._fading then
                    ic.frame:SetAlpha(iconAlpha)
                    ic._fading = nil
                end
            else
                if not ic._isPreview then
                    ic._isPreview = true
                    ic._cachedEntry = nil
                    local previews = GetPreviewIcons()
                    local pIdx = ((i - 1) % #previews) + 1
                    ic.tex:SetTexture(previews[pIdx])
                    ic.tex:SetVertexColor(1, 1, 1, 1)
                    ic.tex:SetAlpha(0.75)
                end
            end
            if i <= histCount then
                ic._isPreview = nil
            end
            if not layoutChanged then
                ic.frame:Show()
            end

            if i == 1 and histCount > 0 then
                local ts = _history[1].timestamp
                if ts ~= _lastAnimTimestamp then
                    _lastAnimTimestamp = ts
                    local animType = sh.iconAnimation or "slide"
                    if animType ~= "none" then
                        PlayIconAnim(ic, animType, dir, iconAlpha)
                    end
                end
            end
        else
            ic.frame:SetScript("OnUpdate", nil)
            ic.frame:SetScale(1)
            ic.frame:Hide()
        end
    end
    _lastIconCount = count
    if layoutChanged then
        _iconLayoutKey = iconSz .. "|" .. gap .. "|" .. dir .. "|" .. count .. "|" .. iconAlpha
    end

    _iconStrip:Show()
    _iconContainer:Show()
end

-- First-class Unlock Mode element.  The frame spans every configured icon in
-- preview mode, giving the strip the same labeled placement box as Combat Timer.
mod.MakeIconHistoryUnlockElement = function(MK)
    local function UnlockGeometry()
        return IconStripGeometry(SavedDB().iconCount or 5)
    end
    return MK({
        key = "EDM_IconHistory",
        label = "Icon History",
        group = "Damage Meters",
        order = 657,
        noResize = true,
        noAnchorTarget = true,
        -- Self-positioning: the container resizes with the LIVE icon count
        -- (casts, fade-outs), and the unlock system's resize re-apply would pin
        -- the stored CENTER of the MAX footprint on every resize -- turning the
        -- fixed newest-icon anchor into centered growth. noInitHook delegates
        -- both the login apply and every resize re-apply to applyPos below
        -- (PositionIconContainer's newest-icon-TOPLEFT compensation).
        noInitHook = true,
        getFrame = function()
            return _iconContainer
        end,
        getSize = function()
            local _, _, _, width, height = UnlockGeometry()
            return width, height
        end,
        isHidden = function()
            return not SavedDB().iconEnabled
        end,
        savePos = function(_, anchorPoint, relPoint, posX, posY)
            -- Unlock Mode stores registered elements as CENTER/CENTER offsets.
            -- Convert that full-container center back to the legacy first-icon
            -- TOPLEFT convention so old profiles and Shift-drag keep agreeing.
            local iconSz, _, dir, width, height = UnlockGeometry()
            local centerX = UIParent:GetWidth() * 0.5 + (posX or 0)
            local centerY = UIParent:GetHeight() * 0.5 + (posY or 0)
            local firstLeft = centerX - width * 0.5
            local firstTop = centerY + height * 0.5
            if dir == "LEFT" then
                firstLeft = firstLeft + width - iconSz
            end
            if dir == "UP" then
                firstTop = firstTop - height + iconSz
            end
            SavedDB().iconPos = { x = firstLeft, y = firstTop }
        end,
        loadPos = function()
            local place = SavedDB().iconPos
            local iconSz, _, dir, width, height = UnlockGeometry()
            local firstLeft = place and place.x or (UIParent:GetWidth() * 0.5 - iconSz * 0.5)
            local firstTop = place and place.y or (UIParent:GetHeight() * 0.5 + iconSz * 0.5)
            local leftX = firstLeft - (dir == "LEFT" and (width - iconSz) or 0)
            local topY = firstTop + (dir == "UP" and (height - iconSz) or 0)
            return {
                point = "CENTER",
                relPoint = "CENTER",
                x = leftX + width * 0.5 - UIParent:GetWidth() * 0.5,
                y = topY - height * 0.5 - UIParent:GetHeight() * 0.5,
            }
        end,
        clearPos = function()
            SavedDB().iconPos = nil
        end,
        applyPos = function()
            PositionIconContainer(
                (CUI._unlockActive and SavedDB().iconCount) or _iconContainer and _iconContainer._layoutCount
            )
        end,
    })
end

-------------------------------------------------------------------------------
--  BAR WINDOW  (standalone, matches DM window styling)
-------------------------------------------------------------------------------
local _barWin
local _barPool = {}
local _barScroll = 0
local _barFontCache = "" -- tracks font changes to avoid per-bar SetFont calls
local _barLayoutCache = "" -- tracks layout changes (barH, spacing, texture)
local _lastBarVisible = 0 -- tracks visible bar count for minimal loop

local function MakeHistoryBar(hostFrame)
    local barFrame = {}
    barFrame.row = CreateFrame("Frame", nil, hostFrame)
    barFrame.row:SetHeight(18)

    -- Icon anchored to row left; fill starts right of icon
    barFrame.icon = barFrame.row:CreateTexture(nil, "OVERLAY")
    barFrame.icon:SetSize(18, 18)
    barFrame.icon:SetPoint("LEFT", barFrame.row, "LEFT", 0, 0)
    local z = SavedDB().iconZoom or 0.08
    barFrame.icon:SetTexCoord(z, 1 - z, z, 1 - z)

    barFrame.fill = CreateFrame("StatusBar", nil, barFrame.row)
    barFrame.fill:SetPoint("TOPLEFT", barFrame.icon, "TOPRIGHT", 0, 0)
    barFrame.fill:SetPoint("BOTTOMRIGHT", barFrame.row, "BOTTOMRIGHT", 0, 0)
    barFrame.fill:SetMinMaxValues(0, 1)
    barFrame.fill:SetValue(1)
    barFrame.fill:SetStatusBarTexture(BAR_TEX)
    -- Blizzard Style: the same track and edge as the meter's own rows
    -- (Classic WoW UI rows stay plain).
    if mod.DMStyle() == "blizzard" then
        barFrame._bg = barFrame.row:CreateTexture(nil, "BACKGROUND")
        mod.DMApplyBlizzBarBg(barFrame)
    end

    local tf = CreateFrame("Frame", nil, barFrame.fill)
    tf:SetAllPoints(barFrame.fill)
    tf:SetFrameLevel(barFrame.fill:GetFrameLevel() + 2)

    local sh = SavedDB()
    local fontStr = sh.textSize or 11

    barFrame.label = tf:CreateFontString(nil, "OVERLAY")
    barFrame.label:SetPoint("LEFT", barFrame.icon, "RIGHT", 4, 0)
    barFrame.label:SetJustifyH("LEFT")
    barFrame.label:SetWordWrap(false)
    SetFont(barFrame.label, fontStr)

    barFrame.rightText = tf:CreateFontString(nil, "OVERLAY")
    barFrame.rightText:SetPoint("RIGHT", tf, "RIGHT", -3, 0)
    barFrame.rightText:SetJustifyH("RIGHT")
    barFrame.rightText:SetWordWrap(false)
    SetFont(barFrame.rightText, fontStr)

    barFrame.label:SetPoint("RIGHT", barFrame.rightText, "LEFT", -4, 0)

    barFrame.row:Hide()
    return barFrame
end

local MEDIA = "Interface\\AddOns\\CludesUIDamageMeters\\Media\\"
local RESIZE_ICON = "Interface\\AddOns\\CludesUI\\media\\icons\\resize_element.png"
local MIN_W, MIN_H = 150, 80

local function BuildBarWindow()
    local sh = SavedDB()
    local dmCfg = mod.EDM.DB()
    if
        not sh.barEnabled
        or ShouldHide(
            sh.barHideInDungeon,
            sh.barHideInRaid,
            sh.barHideInDelve,
            sh.barHideInPvP,
            sh.barHideOutOfInstance
        )
    then
        if _barWin then
            _barWin:Hide()
        end
        return
    end

    if not _barWin then
        local widget = CreateFrame("Frame", "CludesUIDMBarHistory", UIParent)
        widget:SetClampedToScreen(true)
        widget:SetMovable(true)
        widget:SetFrameStrata("MEDIUM")
        widget:EnableMouse(false)
        widget._visSlots = 1
        widget._locked = sh.barLocked or false
        widget._isHovered = false
        _barWin = widget
        -- A cast already underway animates the moment the window shows
        -- (instance rules, hotkey, options, Alt-Z). Starts hidden so the
        -- first Show below runs it too.
        widget:SetScript("OnShow", function()
            if next(_pendingCasts) then
                StartCastAnim(true)
            end
        end)
        widget:Hide()

        widget._bg = widget:CreateTexture(nil, "BACKGROUND")
        widget._bg:SetAllPoints()

        -- Header (inside the classic box's line; flush on every other look)
        local ci = mod.DMClassicInset()
        -- (Its fixed 22, plus the Forever header band's rail under the variant.)
        local heading = CreateFrame("Frame", nil, widget)
        heading:SetHeight(22 + mod.DMFvRail(22))
        heading:SetPoint("TOPLEFT", widget, "TOPLEFT", ci, -ci)
        heading:SetPoint("TOPRIGHT", widget, "TOPRIGHT", -ci, -ci)
        heading:SetFrameLevel(widget:GetFrameLevel() + 5)
        heading:EnableMouse(true)
        widget._hdr = heading

        local hdrBg = heading:CreateTexture(nil, "BACKGROUND")
        hdrBg:SetAllPoints()
        widget._hdrBg = hdrBg

        local titleText = heading:CreateFontString(nil, "OVERLAY")
        titleText:SetPoint("LEFT", heading, "LEFT", 6, mod.DMHdrLift(22))
        SetFont(titleText, 11)
        titleText:SetText("Spell History")
        widget._title = titleText

        -- Header icons (right-aligned, matching DM window style)
        local ICON_A = 0.4
        local ICON_HA = 0.9
        -- Size and gap follow the style (the main window's rule at its
        -- fixed 22 base): ns.DMHdrIconSize / ns.DMHdrIconPad.
        local btnSize = mod.DMHdrIconSize(nil)
        local btnPad = mod.DMHdrIconPad()

        -- artKey: the header key whose stock-style art replaces the glyph
        -- under a stock style (ns.DM_HDR_ART); the glyph stays where none exists.
        local function MakeHdrBtn(texFile, xOff, tooltip, onClick, artKey)
            local button = CreateFrame("Button", nil, heading)
            button:SetSize(btnSize, btnSize)
            button:SetPoint("RIGHT", heading, "RIGHT", xOff, mod.DMHdrLift(22))
            button:SetFrameLevel(heading:GetFrameLevel() + 2)
            local glyph = button:CreateTexture(nil, "ARTWORK")
            glyph:SetAllPoints()
            button._hdrIcon = glyph
            if not mod.DMPaintHdrArt(glyph, artKey) then
                glyph:SetTexture(texFile)
                glyph:SetDesaturated(true)
                glyph:SetVertexColor(1, 1, 1, ICON_A)
            end
            button:SetScript("OnEnter", function()
                if not mod.DMHdrHover(glyph, true) then
                    glyph:SetVertexColor(1, 1, 1, ICON_HA)
                end
                CUI.ShowWidgetTooltip(button, tooltip)
            end)
            button:SetScript("OnLeave", function()
                if not mod.DMHdrHover(glyph, false) then
                    glyph:SetVertexColor(1, 1, 1, ICON_A)
                end
                CUI.HideWidgetTooltip()
            end)
            button:SetScript("OnClick", function()
                CUI.HideWidgetTooltip()
                onClick(button)
            end)
            button._icon = glyph
            return button
        end

        -- Btn 1 (rightmost): Settings
        MakeHdrBtn(MEDIA .. "dm_settings.png", -(btnPad + 2), "Settings", function()
            -- Folded to the mini window: fall through to ShowModule, which unfolds it.
            if mod._optionsOpen and not CUI._panelCollapsed then
                CUI:Hide()
                return
            end
            if CUI.ShowModule then
                CUI:ShowModule("CludesUIDamageMeters")
                C_Timer.After(0, function()
                    CUI:SelectPage("Spell History")
                end)
            end
        end, "settings")

        -- Btn 2: Lock/Unlock
        local lockBtnHdr = MakeHdrBtn(
            widget._locked and (MEDIA .. "dm_locked_top.png") or (MEDIA .. "dm_unlock_top.png"),
            -(btnSize + btnPad * 2 + 2),
            widget._locked and "Locked" or "Unlocked",
            function()
                widget._locked = not widget._locked
                SavedDB().barLocked = widget._locked
                local ic = widget._lockBtn._icon
                if not mod.DMPaintHdrArt(ic, widget._locked and "locked" or "unlocked") then
                    ic:SetTexture(
                        widget._locked and (MEDIA .. "dm_locked_top.png") or (MEDIA .. "dm_unlock_top.png")
                    )
                end
            end,
            widget._locked and "locked" or "unlocked"
        )
        widget._lockBtn = lockBtnHdr
        lockBtnHdr:SetScript("OnEnter", function()
            if not mod.DMHdrHover(lockBtnHdr._icon, true) then
                lockBtnHdr._icon:SetVertexColor(1, 1, 1, ICON_HA)
            end
            CUI.ShowWidgetTooltip(lockBtnHdr, widget._locked and "Locked" or "Unlocked")
        end)

        -- Btn 3: Resize (width drag)
        local resizeBtnHdr = MakeHdrBtn(
            MEDIA .. "dm_width_resize.png",
            -(btnSize * 2 + btnPad * 3 + 2),
            "Resize Width",
            function() end,
            "resize"
        )
        -- Override: drag to resize width
        local resizeStartX, resizeStartW
        local resizeFrame = CreateFrame("Frame")
        resizeFrame:Hide()
        resizeFrame:SetScript("OnUpdate", function()
            if not widget._resizing then
                return
            end
            local cx = GetCursorPosition()
            local es = widget:GetEffectiveScale()
            widget:SetWidth(upper(MIN_W, resizeStartW + (cx / es - resizeStartX)))
        end)
        resizeBtnHdr:SetScript("OnMouseDown", function(_, button)
            if button ~= "LeftButton" or widget._locked then
                return
            end
            local leftX, topY = widget:GetLeft(), widget:GetTop()
            if leftX and topY then
                widget:ClearAllPoints()
                widget:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", leftX, topY)
            end
            local cx = GetCursorPosition()
            resizeStartX = cx / widget:GetEffectiveScale()
            resizeStartW = widget:GetWidth()
            widget._resizing = true
            resizeFrame:Show()
        end)
        resizeBtnHdr:SetScript("OnMouseUp", function(_, button)
            if button ~= "LeftButton" or not widget._resizing then
                return
            end
            widget._resizing = false
            resizeFrame:Hide()
            SavedDB().barWidth = floor(widget:GetWidth() + 0.5)
        end)

        -- Header drag
        heading:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" and not widget._locked then
                widget:StartMoving()
            end
        end)
        heading:SetScript("OnMouseUp", function()
            widget:StopMovingOrSizing()
            local l, t = widget:GetLeft(), widget:GetTop()
            if l and t then
                SavedDB().barPos = { x = l, y = t }
            end
        end)

        -- Content (click-through, mouse wheel only)
        local contentFrame = CreateFrame("Frame", nil, widget)
        contentFrame:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, 0)
        contentFrame:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", 0, 0)
        contentFrame:EnableMouse(false)
        widget._content = contentFrame

        contentFrame:EnableMouseWheel(true)
        contentFrame:SetScript("OnMouseWheel", function(_, delta)
            local maxS = upper(0, #_history - (widget._visSlots or 1))
            _barScroll = upper(0, min(_barScroll - delta, maxS))
            RefreshBarWindow()
        end)
    end

    -- Apply styling (bg from spell history settings, header from DM settings;
    -- the classic header shade follows this window's own colour)
    mod.DMPaintWindowBg(_barWin._bg, sh.bgR or 0, sh.bgG or 0, sh.bgB or 0, sh.bgAlpha or 0.25, true)

    local hc = dmCfg.hdrBgColor
    local hR, hG, hB = hc and hc.r or 0x1B / 255, hc and hc.g or 0x1B / 255, hc and hc.b or 0x1B / 255
    mod.DMPaintHeaderBg(
        _barWin._hdrBg,
        hR,
        hG,
        hB,
        dmCfg.hdrBgAlpha or 1,
        sh.bgR or 0,
        sh.bgG or 0,
        sh.bgB or 0
    )

    local tR, tG, tB
    if dmCfg.hdrTextUseAccent ~= false then
        tR, tG, tB = mod.DMTitleRGB()
    else
        local tc = dmCfg.hdrTextColor
        tR = tc and tc.r or 1
        tG = tc and tc.g or 1
        tB = tc and tc.b or 1
    end
    _barWin._title:SetTextColor(tR, tG, tB, 1)

    -- Hide/show top bar
    local hideTop = sh.hideTopBar
    local ci = mod.DMClassicInset()
    if hideTop then
        _barWin._hdr:Hide()
    else
        _barWin._hdr:Show()
    end
    _barWin._content:ClearAllPoints()
    if hideTop then
        _barWin._content:SetPoint("TOPLEFT", _barWin, "TOPLEFT", ci, -ci)
    else
        _barWin._content:SetPoint("TOPLEFT", _barWin._hdr, "BOTTOMLEFT", 0, 0)
    end
    _barWin._content:SetPoint("BOTTOMRIGHT", _barWin, "BOTTOMRIGHT", -ci, ci)

    -- Size: width from DB, height auto-calculated from maxBars (plus the
    -- classic box's inset above and below)
    local hdrH = hideTop and 0 or (22 + mod.DMFvRail(22))
    local maxBars = sh.maxBars or 5
    local _, _, stride =
        mod._RowMetrics(sh.shBarHeight or 18, dmCfg.barSpacing or 2, _barWin:GetEffectiveScale())
    local autoH = hdrH + maxBars * stride + ci * 2
    _barWin:SetSize(sh.barWidth or 300, autoH)
    _barWin._locked = sh.barLocked or false
    local place = sh.barPos
    if place and place.x and place.y then
        _barWin:ClearAllPoints()
        _barWin:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", place.x, place.y)
    elseif not _barWin._positioned then
        _barWin:ClearAllPoints()
        _barWin:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        _barWin._positioned = true
    end

    while #_barPool < BAR_POOL_SIZE do
        _barPool[#_barPool + 1] = MakeHistoryBar(_barWin._content)
    end

    _barWin:Show()
    RefreshBarWindow()
end

RefreshBarWindow = function()
    if not _barWin or not _barWin:IsShown() then
        return
    end

    local dmCfg = mod.EDM.DB()
    local sh = SavedDB()
    local barH, barSp, stride =
        mod._RowMetrics(sh.shBarHeight or 18, dmCfg.barSpacing or 2, _barWin:GetEffectiveScale())
    local texPath = GetBarTexturePath()
    local fontSize = sh.textSize or 11
    local contentFrame = _barWin._content
    local frameH = contentFrame:GetHeight()
    local visSlots = upper(1, floor(frameH / stride + 0.5))
    _barWin._visSlots = visSlots

    -- Text color from spell history settings
    local txR, txG, txB
    if sh.textColorUseAccent then
        txR, txG, txB = GetAccentRGB()
    else
        local tc = sh.textColor
        txR = tc and tc.r or 1
        txG = tc and tc.g or 1
        txB = tc and tc.b or 1
    end

    -- Re-apply fonts to ALL pool bars when settings change (not just visible ones)
    local fontKey = fontSize
        .. "|"
        .. CUI.GetFontPath("damageMeters")
        .. "|"
        .. CUI.GetFontOutlineFlag("damageMeters")
    local fontChanged = (fontKey ~= _barFontCache)
    if fontChanged then
        _barFontCache = fontKey
        for fi = 1, #_barPool do
            SetFont(_barPool[fi].label, fontSize)
            SetFont(_barPool[fi].rightText, fontSize)
        end
    end

    -- Precompute normal bar color outside loop (OutcomeColor calls DB per bar)
    local nR, nG, nB = OutcomeColor("success")
    local barAlpha = sh.barOpacity or 1
    local stR, stG, stB = CLR_STOPPED[1], CLR_STOPPED[2], CLR_STOPPED[3]

    local sum = min(#_history, sh.maxBars or 5)
    local loopEnd = upper(visSlots, _lastBarVisible)
    local barIconZoom = sh.iconZoom or 0.08

    -- Layout key: only rebuild positions/sizes when settings change
    local layoutKey = barH .. "|" .. barSp .. "|" .. texPath
    local layoutChanged = (layoutKey ~= _barLayoutCache)
    if layoutChanged then
        _barLayoutCache = layoutKey
    end

    for i = 1, loopEnd do
        local barFrame = _barPool[i]
        if not barFrame then
            break
        end
        local position = _barScroll + i
        if i <= visSlots and position <= sum then
            local record = _history[position]

            if barFrame._cachedZoom ~= barIconZoom then
                barFrame._cachedZoom = barIconZoom
                barFrame.icon:SetTexCoord(barIconZoom, 1 - barIconZoom, barIconZoom, 1 - barIconZoom)
            end

            -- Layout: only on settings change or slot reuse
            if layoutChanged or barFrame._cachedSlot ~= i then
                barFrame._cachedSlot = i
                local posY = -(i - 1) * stride
                barFrame.row:ClearAllPoints()
                barFrame.row:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, posY)
                barFrame.row:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", 0, posY)
                barFrame.row:SetHeight(barH)
                barFrame.fill:SetStatusBarTexture(texPath)
                -- Blizzard Style: the stock bevel over the user's texture
                -- (none under Classic WoW UI).
                if mod.DMStyle() == "blizzard" then
                    mod.DMApplyBlizzFill(barFrame.fill)
                end
                barFrame.icon:SetSize(barH, barH)
                barFrame._cachedEntry = nil -- force content rebuild
            end

            -- Content: only when entry changes
            if barFrame._cachedEntry ~= record then
                barFrame._cachedEntry = record
                if record.icon then
                    barFrame.icon:SetTexture(record.icon)
                    barFrame.icon:Show()
                else
                    barFrame.icon:Hide()
                end
                barFrame.label:SetText(record.spellName or "?")
                barFrame._cachedStatus = nil -- force color/fill rebuild
                barFrame._cachedFillDone = nil -- force fill value reset
            end

            -- Color + fill: update when status changes or on active casts
            local status = record.status
            if barFrame._cachedStatus ~= status then
                barFrame._cachedStatus = status
                local cr, cg, cb
                if status == "failed" or status == "interrupted" then
                    cr, cg, cb = stR, stG, stB
                else
                    cr, cg, cb = nR, nG, nB
                end
                barFrame.fill:SetStatusBarColor(cr, cg, cb, barAlpha)
            end

            -- Fill value: always set for active casts, once for finished
            if record.fillProgress then
                barFrame.fill:SetValue(record.fillProgress)
            elseif status == "casting" or status == "channeling" then
                local nowTime = GetTime()
                local dur = record.endTime - record.startTime
                if dur > 0 then
                    local progress = status == "channeling" and (record.endTime - nowTime) / dur
                        or (nowTime - record.startTime) / dur
                    barFrame.fill:SetValue(min(upper(progress, 0), 1))
                else
                    barFrame.fill:SetValue(1)
                end
            elseif not barFrame._cachedFillDone then
                barFrame._cachedFillDone = true
                barFrame.fill:SetValue(1)
            end

            -- Text color: only on settings change
            if layoutChanged or not barFrame._cachedTxColor then
                barFrame._cachedTxColor = true
                barFrame.label:SetTextColor(txR, txG, txB, 1)
                barFrame.rightText:SetTextColor(txR, txG, txB, 1)
            end

            barFrame.rightText:SetText(BuildRightText(record))
            barFrame.row:Show()
        else
            if barFrame then
                barFrame.row:Hide()
                barFrame._cachedSlot = nil
                barFrame._cachedEntry = nil
                barFrame._cachedStatus = nil
                barFrame._cachedFillDone = nil
                barFrame._cachedTxColor = nil
            end
        end
    end
    _lastBarVisible = visSlots
end

-------------------------------------------------------------------------------
--  Active-cast fill animation
--  Only runs while there are pending (in-progress) casts to animate and the
--  bar window is visible.  Stops itself when all casts resolve or the window
--  hides; the window's OnShow restarts it.  Zero cost when idle or hidden.
-------------------------------------------------------------------------------
-- Lightweight per-frame updater: only touches fill values + right text on
-- bars with active casts.  Full RefreshBarWindow runs on PushEntry/Finish.
local _castAnimFrame = CreateFrame("Frame")
_castAnimFrame:Hide()
_castAnimFrame:SetScript("OnUpdate", function(self)
    if not next(_pendingCasts) then
        self:Hide()
        return
    end
    if not _barWin or not _barWin:IsVisible() then
        self:Hide()
        return
    end
    local nowTime = GetTime()
    local visSlots = _barWin._visSlots or 5
    local scroll = _barScroll or 0
    for i = 1, min(visSlots, BAR_POOL_SIZE) do
        local position = scroll + i
        local record = _history[position]
        if not record then
            break
        end
        local status = record.status
        if status == "casting" or status == "channeling" then
            local barFrame = _barPool[i]
            if barFrame and barFrame.row:IsShown() then
                local dur = record.endTime - record.startTime
                if dur > 0 then
                    local progress = status == "channeling" and (record.endTime - nowTime) / dur
                        or (nowTime - record.startTime) / dur
                    barFrame.fill:SetValue(min(upper(progress, 0), 1))
                end
                barFrame.rightText:SetText(BuildRightText(record))
            end
        end
    end
end)

-- onShow: called from the bar window's OnShow, which already means it is visible.
StartCastAnim = function(onShow)
    if onShow or (_barWin and _barWin:IsVisible()) then
        _castAnimFrame:Show()
    end
end
local function StopCastAnim()
    _castAnimFrame:Hide()
end

-------------------------------------------------------------------------------
--  Public API
-------------------------------------------------------------------------------
function mod.ApplySpellHistory()
    local sh = SavedDB()
    local isActive = sh.iconEnabled or sh.barEnabled

    -- Dynamic event registration: zero overhead when disabled
    if isActive then
        RegisterEvents()
    else
        UnregisterEvents()
        StopCastAnim()
    end

    if sh.iconEnabled then
        BuildIconStrip()
    elseif _iconContainer then
        _iconContainer:Hide()
    end

    if sh.barEnabled then
        BuildBarWindow()
    elseif _barWin then
        _barWin:Hide()
    end

    -- Keep disabled cost at zero: only subscribe to unlock transitions while
    -- Icon History itself is enabled.
    if sh.iconEnabled and not mod._iconUnlockListenerRegistered and CUI.RegisterUnlockModeListener then
        mod._iconUnlockListenerRegistered = true
        CUI:RegisterUnlockModeListener("EDM_IconHistory", function()
            if SavedDB().iconEnabled then
                BuildIconStrip()
            end
        end)
    elseif not sh.iconEnabled and mod._iconUnlockListenerRegistered and CUI.UnregisterUnlockModeListener then
        CUI:UnregisterUnlockModeListener("EDM_IconHistory")
        mod._iconUnlockListenerRegistered = nil
    end
end

function mod.RefreshSpellHistoryProfile()
    _shDB = nil
    _iconLayoutKey = ""
    mod.ApplySpellHistory()
end

-------------------------------------------------------------------------------
--  Init (deferred to PLAYER_LOGIN so DM DB is ready)
-------------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    C_Timer.After(0.1, function()
        _shDB = nil -- force defaults merge on first access
        mod.ApplySpellHistory()
    end)
end)

-- Re-evaluate visibility when entering/leaving instances; refresh preview on spec change
local zoneFrame = CreateFrame("Frame")
zoneFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
zoneFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
zoneFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
zoneFrame:SetScript("OnEvent", function(_, evt)
    if evt == "PLAYER_SPECIALIZATION_CHANGED" then
        _previewIcons = nil
    end
    if mod.ApplySpellHistory then
        mod.ApplySpellHistory()
    end
end)
