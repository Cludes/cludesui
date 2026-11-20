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
local floor, format, min, max = math.floor, string.format, math.min, math.max
local GetTime = GetTime

-- Spell info cache: spellID -> { name, iconID } (never changes for a given ID)
local _spellInfoCache = {}

-- Cached DB accessor; defaults are merged once at init, not per-call
local _shDB
local function DB()
    if _shDB then
        return _shDB
    end
    local skinData = mod.EDM.DB()
    if not skinData.spellHistory then
        skinData.spellHistory = {}
    end
    local historyCfg = skinData.spellHistory
    for k, v in pairs(SH_DEFAULTS) do
        if historyCfg[k] == nil then
            historyCfg[k] = v
        end
    end
    _shDB = historyCfg
    return historyCfg
end

local function SetFont(fontStr, size)
    CludesUI.ApplyModuleFont(fontStr, nil, size, "damageMeters")
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
    local historyCfg = DB()
    local castKey = historyCfg.spellHistoryBarTexture
    if not castKey or castKey == "match" then
        castKey = (dmCfg and dmCfg.barTexture) or "none"
    end
    local texTable = _G._CUDM_BarTextures
    if texTable then
        return CUI.ResolveTexturePath(texTable, castKey, BAR_TEX)
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

local function OutcomeColor(statusText)
    if statusText == "failed" or statusText == "interrupted" then
        return CLR_STOPPED[1], CLR_STOPPED[2], CLR_STOPPED[3]
    end
    local historyCfg = DB()
    if historyCfg.barColorUseClass then
        local _, class = UnitClass("player")
        local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] and CUI.GetClassColor(class)
        if cc then
            return cc.r, cc.g, cc.b
        end
    end
    if historyCfg.barColorUseAccent then
        return GetAccentRGB()
    end
    local color = historyCfg.barColor
    return color and color.r or 0.298, color and color.g or 0.565, color and color.b or 0.494
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
    local statusText = record.status
    -- Active cast: show elapsed time counting up
    if statusText == "casting" or statusText == "channeling" then
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
    local goal = record.target
    local isSecret = goal and issecretvalue and issecretvalue(goal)
    local hasTarget = goal and (isSecret or goal ~= "")
    -- Strip realm suffix for non-secret names (secret values pass through to FontString as-is)
    if hasTarget and not isSecret and not outcomeStr and Ambiguate then
        goal = Ambiguate(goal, "short")
    end
    local rightSide = outcomeStr or (hasTarget and goal) or nil
    local outcome
    if castStr ~= "" and rightSide then
        outcome = castStr .. "  " .. rightSide
    elseif castStr ~= "" then
        outcome = castStr
    elseif rightSide then
        outcome = rightSide
    else
        outcome = ""
    end
    return outcome
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
    local historyCfg = DB()
    if historyCfg.iconEnabled then
        BuildIconStrip()
    end
    if historyCfg.barEnabled then
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
        for castKey, fam in pairs(CUI.CONSUMABLES) do
            if not fv or castKey == "healthstone" then
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

local function FinishPending(castGuid, statusText)
    _pendingTargets[castGuid] = nil
    local record = _pendingCasts[castGuid]
    if not record then
        return
    end
    -- Don't downgrade a success (server accepted) to failed/interrupted (client race)
    if record.status == "success" then
        _pendingCasts[castGuid] = nil
        return
    end
    -- Snapshot fill progress for interrupted/failed casts so the bar freezes
    if statusText == "interrupted" or statusText == "failed" then
        local nowTime = GetTime()
        local dur = record.endTime - record.startTime
        if dur > 0 then
            if record.isChannel then
                record.fillProgress = max(0, min(1, (record.endTime - nowTime) / dur))
            else
                record.fillProgress = max(0, min(1, (nowTime - record.startTime) / dur))
            end
        end
    end
    record.status = statusText
    record.endTime = GetTime()
    if record.startTime then
        record.castDuration = record.endTime - record.startTime
    end
    _pendingCasts[castGuid] = nil
    RefreshViews()
end

-------------------------------------------------------------------------------
--  Event-driven spell tracking
--  Events are only registered when at least one feature is enabled.
-------------------------------------------------------------------------------
local _eventsActive = false
local watcher = CreateFrame("Frame")

local function OnSpellEvent(_, evt, unitToken, ...)
    if unitToken ~= "player" then
        return
    end

    -- UNIT_SPELLCAST_SENT has unique args: unit, target, castGUID, spellID
    if evt == "UNIT_SPELLCAST_SENT" then
        local goal, otherCastGuid, sentSpellID = ...
        if otherCastGuid and goal then
            _pendingTargets[otherCastGuid] = goal
        end
        if otherCastGuid and sentSpellID and _consumableSpells[sentSpellID] then
            _sentConsumable = otherCastGuid
        end
        return
    end

    local castGuid, spellId = ...

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
            target = castGuid and _pendingTargets[castGuid],
            startTime = (startMS or 0) / 1000,
            endTime = (endMS or 0) / 1000,
            castDuration = ((endMS or 0) - (startMS or 0)) / 1000,
            status = "casting",
            isInstant = false,
            isChannel = false,
            consumable = _consumableSpells[spellId] and true or nil,
            timestamp = GetTime(),
        }
        if castGuid then
            _pendingCasts[castGuid] = record
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
            target = castGuid and _pendingTargets[castGuid],
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
        if castGuid then
            _pendingCasts[castGuid] = record
        end
        PushEntry(record)
        StartCastAnim()
    elseif evt == "UNIT_SPELLCAST_SUCCEEDED" then
        if castGuid and _pendingCasts[castGuid] then
            FinishPending(castGuid, "success")
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
                if castGuid and castGuid == _sentConsumable then
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
            local covered = false
            -- Check pending casts first (different/nil castGUID race)
            for groupId, pe in pairs(_pendingCasts) do
                if pe.spellID == spellId then
                    FinishPending(groupId, "success")
                    covered = true
                    break
                end
            end
            -- Check recent history (INTERRUPTED already consumed the entry)
            if not covered then
                for hi = 1, min(#_history, 5) do
                    local he = _history[hi]
                    if he.spellID == spellId and (he.status == "interrupted" or he.status == "failed") then
                        he.status = "success"
                        he.fillProgress = nil
                        covered = true
                        RefreshViews()
                        break
                    end
                end
            end
            if not covered then
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
                    target = castGuid and _pendingTargets[castGuid],
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
        if castGuid then
            FinishPending(castGuid, "failed")
        end
    elseif evt == "UNIT_SPELLCAST_INTERRUPTED" then
        if castGuid then
            FinishPending(castGuid, "interrupted")
        end
    elseif evt == "UNIT_SPELLCAST_STOP" then
        if not castGuid then
            return
        end
        local record = _pendingCasts[castGuid]
        if record and record.status == "casting" then
            local groupId = castGuid
            C_Timer.After(0, function()
                if _pendingCasts[groupId] and _pendingCasts[groupId].status == "casting" then
                    FinishPending(groupId, "failed")
                end
            end)
        end
    elseif evt == "UNIT_SPELLCAST_CHANNEL_STOP" then
        _activeChannelSpell = nil
        if castGuid then
            _pendingTargets[castGuid] = nil
            local record = _pendingCasts[castGuid]
            if record then
                if record.status == "channeling" then
                    record.status = "success"
                end
                record.endTime = GetTime()
                if record.startTime then
                    record.castDuration = record.endTime - record.startTime
                end
                _pendingCasts[castGuid] = nil
            end
        end
    end
end

local function RegisterEvents()
    if _eventsActive then
        return
    end
    BuildConsumableSpells()
    watcher:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player") -- player only (was global, fired for all units)
    watcher:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    watcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    watcher:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    watcher:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
    watcher:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    watcher:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    watcher:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    watcher:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    watcher:SetScript("OnEvent", OnSpellEvent)
    _eventsActive = true
end

local function UnregisterEvents()
    if not _eventsActive then
        return
    end
    watcher:UnregisterAllEvents()
    watcher:SetScript("OnEvent", nil)
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
local function IconStripGeometry(total)
    local historyCfg = DB()
    local iconSize = SnapSize(historyCfg.iconSize or 24)
    local gap = historyCfg.iconSpacing or 1
    local direction = historyCfg.growDirection or "LEFT"
    total = max(1, total or historyCfg.iconCount or 5)
    local span = total * iconSize + (total - 1) * gap
    local horizontal = direction == "LEFT" or direction == "RIGHT"
    local w = horizontal and span or iconSize
    local height = horizontal and iconSize or span
    local leftOffset = direction == "LEFT" and (span - iconSize) or 0
    local upOffset = direction == "UP" and (span - iconSize) or 0
    return iconSize, gap, direction, w, height, leftOffset, upOffset
end

local function PositionIconContainer(total)
    if not _iconContainer or not _iconStrip then
        return
    end
    local iconSize, _, direction, w, height, leftOffset, upOffset = IconStripGeometry(total)

    _iconContainer:SetSize(w, height)
    _iconStrip:SetSize(iconSize, iconSize)
    _iconStrip:ClearAllPoints()
    if direction == "RIGHT" then
        _iconStrip:SetPoint("LEFT", _iconContainer, "LEFT", 0, 0)
    elseif direction == "LEFT" then
        _iconStrip:SetPoint("RIGHT", _iconContainer, "RIGHT", 0, 0)
    elseif direction == "DOWN" then
        _iconStrip:SetPoint("TOP", _iconContainer, "TOP", 0, 0)
    else
        _iconStrip:SetPoint("BOTTOM", _iconContainer, "BOTTOM", 0, 0)
    end

    -- The shared anchor system owns placement while this element is linked.
    if CUI.IsUnlockAnchored and CUI.IsUnlockAnchored("EDM_IconHistory") then
        return
    end

    local place = DB().iconPos
    local firstLeft, firstTop
    if place and place.x and place.y then
        firstLeft, firstTop = place.x, place.y
    else
        firstLeft = UIParent:GetWidth() * 0.5 - iconSize * 0.5
        firstTop = UIParent:GetHeight() * 0.5 + iconSize * 0.5
    end
    _iconContainer:ClearAllPoints()
    _iconContainer:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", firstLeft - leftOffset, firstTop + upOffset)
end

local function SaveIconPositionFromFrame(total)
    if not _iconContainer then
        return
    end
    local leftX, topY = _iconContainer:GetLeft(), _iconContainer:GetTop()
    if not leftX or not topY then
        return
    end
    local _, _, _, _, _, leftOffset, upOffset = IconStripGeometry(total)
    DB().iconPos = { x = leftX + leftOffset, y = topY - upOffset }
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
        for _, iconCell in ipairs(_iconPool) do
            iconCell.frame:EnableMouse(false)
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
local function ScheduleFade(fadeSecs, maxIcons)
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
        if age < fadeSecs then
            local skinData = fadeSecs - age
            if not nextIn or skinData < nextIn then
                nextIn = skinData
            end
        elseif age < fadeSecs + FADE_DUR then
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
            _fadeDriver:SetScript("OnUpdate", function(_, elapsed)
                acc = acc + elapsed
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
            if (DB().iconFadeTime or 0) <= 0 then
                return
            end
            local nowTime = GetTime()
            cs = cs or nowTime
            for i = 1, #_history do
                local e = _history[i]
                local base = FadeBase(e)
                e._fadeBase = base + (nowTime - max(cs, base))
            end
            BuildIconStrip()
        end
    end)
end

-- Plays a one-shot intro animation on an icon frame.
-- Uses dt-accumulated OnUpdate for smooth sub-frame interpolation.
-- Only called on icon 1, which always rests at CENTER of _iconStrip.
local function PlayIconAnim(iconCell, animType, direction, targetAlpha)
    local frame = iconCell.frame
    targetAlpha = targetAlpha or 1

    -- Kill any in-progress animation and snap to rest position.
    -- Using hardcoded rest anchor (icon 1 = CENTER,0,0) instead of
    -- GetPoint, which returns mid-animation displacement on rapid casts.
    frame:SetScript("OnUpdate", nil)
    frame:SetScale(1)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", _iconStrip, "CENTER", 0, 0)

    local p1, rel, relP, origX, origY = "CENTER", _iconStrip, "CENTER", 0, 0

    -- Compute starting displacement for slide types
    local dx, dy = 0, 0
    if animType == "slide" then
        if direction == "LEFT" then
            dx = ANIM_SLIDE_PX
        elseif direction == "RIGHT" then
            dx = -ANIM_SLIDE_PX
        elseif direction == "UP" then
            dy = -ANIM_SLIDE_PX
        else
            dy = ANIM_SLIDE_PX
        end
    end

    local isFly = (animType == "fly")
    local elapsed = 0
    local startAlpha = targetAlpha * 0.5

    frame:SetAlpha(startAlpha)
    if isFly then
        frame:SetScale(1.35)
    end
    if dx ~= 0 or dy ~= 0 then
        frame:SetPoint(p1, rel, relP, origX + dx, origY + dy)
    end

    frame:SetScript("OnUpdate", function(self, dt)
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
    local iconCell = {}
    iconCell.frame = CreateFrame("Frame", nil, hostFrame)
    iconCell.frame:EnableMouse(false)
    -- Shift+drag on any icon moves the entire strip
    iconCell.frame:SetScript("OnMouseDown", function(_, button)
        StartIconDrag(button)
    end)
    iconCell.frame:SetScript("OnMouseUp", StopIconDrag)
    local backdrop = iconCell.frame:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(0, 0, 0, 0.4)
    iconCell.bg = backdrop
    iconCell.tex = iconCell.frame:CreateTexture(nil, "ARTWORK")
    iconCell.tex:SetAllPoints()
    local z = DB().iconZoom or 0.08
    iconCell.tex:SetTexCoord(z, 1 - z, z, 1 - z)
    iconCell.frame:Hide()
    return iconCell
end

-- Preview icons: random spells from the player's action bars
local _previewIcons
local function GetPreviewIcons()
    if _previewIcons then
        return _previewIcons
    end
    _previewIcons = {}
    -- Pull from action bars first (most recognizable spells)
    for slot = 1, 120 do
        local actionType, ident = GetActionInfo(slot)
        if actionType == "spell" and ident and ident > 0 then
            local texture = GetActionTexture(slot)
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
    local historyCfg = DB()
    if
        not historyCfg.iconEnabled
        or ShouldHide(
            historyCfg.iconHideInDungeon,
            historyCfg.iconHideInRaid,
            historyCfg.iconHideInDelve,
            historyCfg.iconHideInPvP,
            historyCfg.iconHideOutOfInstance
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
            for _, iconCell in ipairs(_iconPool) do
                iconCell.frame:EnableMouse(enabled)
            end
        end
        modFrame:SetScript("OnEvent", function(_, _, castKey, down)
            if castKey == "LSHIFT" or castKey == "RSHIFT" then
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

    local iconSize = SnapSize(historyCfg.iconSize or 24)
    local gap = historyCfg.iconSpacing or 1
    local direction = historyCfg.growDirection or "LEFT"
    local zoomPct = historyCfg.iconZoom or 0.08

    local maxIcons = historyCfg.iconCount or 5
    local historyCount = min(#_history, maxIcons)

    -- Fade-out: out of combat, entries past fadeTime+FADE_DUR drop off the
    -- strip (newest first, so the scan stops at the first faded one) and the
    -- clock re-arms for whatever comes next. In combat nothing runs; the
    -- REGEN watcher restarts the clock. fadeNow doubles as the "fade math
    -- active" flag for the alpha pass in the icon loop below.
    local fadeSecs = historyCfg.iconFadeTime or 0
    local fadeNow
    if fadeSecs > 0 then
        EnsureFadeEvents()
        if not InCombatLockdown() then
            fadeNow = GetTime()
            if historyCount > 0 then
                local visible = 0
                for i = 1, historyCount do
                    if fadeNow - FadeBase(_history[i]) < fadeSecs + FADE_DUR then
                        visible = i
                    else
                        break
                    end
                end
                historyCount = visible
            end
            ScheduleFade(fadeSecs, maxIcons)
        end
    else
        StopFadeClock()
    end

    -- Unlock Mode always reserves the configured maximum footprint. Live
    -- history and fade state may change the icon contents, but never the mover
    -- size while the user is positioning it. The options preview keeps its
    -- existing behavior and does not backfill slots vacated by faded icons.
    local showPreview = CUI._unlockActive
        or (mod._optionsOpen and historyCount < maxIcons and not (fadeSecs > 0 and #_history > 0))
    local total = showPreview and maxIcons or historyCount

    -- Nothing to show: hide the strip entirely
    if total == 0 then
        _iconContainer:Hide()
        return
    end

    -- Position and size only on layout change (checked after count is known)
    local iconAlphaCheck = historyCfg.iconOpacity or 1
    local needsLayout = (iconSize .. "|" .. gap .. "|" .. direction .. "|" .. total .. "|" .. iconAlphaCheck)
        ~= _iconLayoutKey
    if needsLayout then
        _iconContainer._layoutCount = total
        PositionIconContainer(total)
    end

    while #_iconPool < ICON_POOL_SIZE do
        _iconPool[#_iconPool + 1] = MakeIcon(_iconStrip)
    end

    -- Layout only changes when settings change; content changes every cast.
    local iconAlpha = iconAlphaCheck
    local layoutChanged = needsLayout
    local loopEnd = max(total, _lastIconCount or 0)

    for i = 1, loopEnd do
        local iconCell = _iconPool[i]
        if not iconCell then
            break
        end
        if i <= total then
            if iconCell._cachedZoom ~= zoomPct then
                iconCell._cachedZoom = zoomPct
                iconCell.tex:SetTexCoord(zoomPct, 1 - zoomPct, zoomPct, 1 - zoomPct)
            end
            if layoutChanged then
                iconCell.frame:SetScript("OnUpdate", nil)
                iconCell.frame:SetScale(1)
                iconCell.frame:SetSize(iconSize, iconSize)
                iconCell.frame:ClearAllPoints()
                local off = (i - 1) * (iconSize + gap)
                if i == 1 then
                    iconCell.frame:SetPoint("CENTER", _iconStrip, "CENTER", 0, 0)
                elseif direction == "RIGHT" then
                    iconCell.frame:SetPoint("CENTER", _iconStrip, "CENTER", off, 0)
                elseif direction == "LEFT" then
                    iconCell.frame:SetPoint("CENTER", _iconStrip, "CENTER", -off, 0)
                elseif direction == "DOWN" then
                    iconCell.frame:SetPoint("CENTER", _iconStrip, "CENTER", 0, -off)
                else
                    iconCell.frame:SetPoint("CENTER", _iconStrip, "CENTER", 0, off)
                end
                iconCell.frame:SetAlpha(iconAlpha)
                iconCell.frame:Show()
            end

            if i <= historyCount then
                local record = _history[i]
                -- Only update texture/color when entry changes
                if iconCell._cachedEntry ~= record then
                    iconCell._cachedEntry = record
                    if record.icon then
                        iconCell.tex:SetTexture(record.icon)
                    end
                    iconCell._cachedStatus = nil
                end
                local st = record.status
                if iconCell._cachedStatus ~= st then
                    iconCell._cachedStatus = st
                    if st == "failed" or st == "interrupted" then
                        iconCell.tex:SetVertexColor(CLR_STOPPED[1], CLR_STOPPED[2], CLR_STOPPED[3], 1)
                    else
                        iconCell.tex:SetVertexColor(1, 1, 1, 1)
                    end
                    iconCell.tex:SetAlpha(1)
                end
                if fadeNow then
                    local age = fadeNow - FadeBase(record)
                    if age > fadeSecs then
                        local k = 1 - (age - fadeSecs) / FADE_DUR
                        if k < 0 then
                            k = 0
                        end
                        iconCell.frame:SetAlpha(iconAlpha * k)
                        iconCell._fading = true
                    elseif iconCell._fading then
                        iconCell.frame:SetAlpha(iconAlpha)
                        iconCell._fading = nil
                    end
                elseif iconCell._fading then
                    iconCell.frame:SetAlpha(iconAlpha)
                    iconCell._fading = nil
                end
            else
                if not iconCell._isPreview then
                    iconCell._isPreview = true
                    iconCell._cachedEntry = nil
                    local previews = GetPreviewIcons()
                    local pIdx = ((i - 1) % #previews) + 1
                    iconCell.tex:SetTexture(previews[pIdx])
                    iconCell.tex:SetVertexColor(1, 1, 1, 1)
                    iconCell.tex:SetAlpha(0.75)
                end
            end
            if i <= historyCount then
                iconCell._isPreview = nil
            end
            if not layoutChanged then
                iconCell.frame:Show()
            end

            if i == 1 and historyCount > 0 then
                local ts = _history[1].timestamp
                if ts ~= _lastAnimTimestamp then
                    _lastAnimTimestamp = ts
                    local animType = historyCfg.iconAnimation or "slide"
                    if animType ~= "none" then
                        PlayIconAnim(iconCell, animType, direction, iconAlpha)
                    end
                end
            end
        else
            iconCell.frame:SetScript("OnUpdate", nil)
            iconCell.frame:SetScale(1)
            iconCell.frame:Hide()
        end
    end
    _lastIconCount = total
    if layoutChanged then
        _iconLayoutKey = iconSize .. "|" .. gap .. "|" .. direction .. "|" .. total .. "|" .. iconAlpha
    end

    _iconStrip:Show()
    _iconContainer:Show()
end

-- First-class Unlock Mode element.  The frame spans every configured icon in
-- preview mode, giving the strip the same labeled placement box as Combat Timer.
mod.MakeIconHistoryUnlockElement = function(MK)
    local function UnlockGeometry()
        return IconStripGeometry(DB().iconCount or 5)
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
            local _, _, _, w, height = UnlockGeometry()
            return w, height
        end,
        isHidden = function()
            return not DB().iconEnabled
        end,
        savePos = function(_, anchorPoint, relPoint, posX, posY)
            -- Unlock Mode stores registered elements as CENTER/CENTER offsets.
            -- Convert that full-container center back to the legacy first-icon
            -- TOPLEFT convention so old profiles and Shift-drag keep agreeing.
            local iconSize, _, direction, w, height = UnlockGeometry()
            local centerX = UIParent:GetWidth() * 0.5 + (posX or 0)
            local centerY = UIParent:GetHeight() * 0.5 + (posY or 0)
            local firstLeft = centerX - w * 0.5
            local firstTop = centerY + height * 0.5
            if direction == "LEFT" then
                firstLeft = firstLeft + w - iconSize
            end
            if direction == "UP" then
                firstTop = firstTop - height + iconSize
            end
            DB().iconPos = { x = firstLeft, y = firstTop }
        end,
        loadPos = function()
            local place = DB().iconPos
            local iconSize, _, direction, w, height = UnlockGeometry()
            local firstLeft = place and place.x or (UIParent:GetWidth() * 0.5 - iconSize * 0.5)
            local firstTop = place and place.y or (UIParent:GetHeight() * 0.5 + iconSize * 0.5)
            local leftX = firstLeft - (direction == "LEFT" and (w - iconSize) or 0)
            local topY = firstTop + (direction == "UP" and (height - iconSize) or 0)
            return {
                point = "CENTER",
                relPoint = "CENTER",
                x = leftX + w * 0.5 - UIParent:GetWidth() * 0.5,
                y = topY - height * 0.5 - UIParent:GetHeight() * 0.5,
            }
        end,
        clearPos = function()
            DB().iconPos = nil
        end,
        applyPos = function()
            PositionIconContainer(
                (CUI._unlockActive and DB().iconCount) or _iconContainer and _iconContainer._layoutCount
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
    local z = DB().iconZoom or 0.08
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

    local historyCfg = DB()
    local fontStr = historyCfg.textSize or 11

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
    local historyCfg = DB()
    local dmCfg = mod.EDM.DB()
    if
        not historyCfg.barEnabled
        or ShouldHide(
            historyCfg.barHideInDungeon,
            historyCfg.barHideInRaid,
            historyCfg.barHideInDelve,
            historyCfg.barHideInPvP,
            historyCfg.barHideOutOfInstance
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
        widget._locked = historyCfg.barLocked or false
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

        local title = heading:CreateFontString(nil, "OVERLAY")
        title:SetPoint("LEFT", heading, "LEFT", 6, mod.DMHdrLift(22))
        SetFont(title, 11)
        title:SetText("Spell History")
        widget._title = title

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
            local iconTex = button:CreateTexture(nil, "ARTWORK")
            iconTex:SetAllPoints()
            button._hdrIcon = iconTex
            if not mod.DMPaintHdrArt(iconTex, artKey) then
                iconTex:SetTexture(texFile)
                iconTex:SetDesaturated(true)
                iconTex:SetVertexColor(1, 1, 1, ICON_A)
            end
            button:SetScript("OnEnter", function()
                if not mod.DMHdrHover(iconTex, true) then
                    iconTex:SetVertexColor(1, 1, 1, ICON_HA)
                end
                CUI.ShowWidgetTooltip(button, tooltip)
            end)
            button:SetScript("OnLeave", function()
                if not mod.DMHdrHover(iconTex, false) then
                    iconTex:SetVertexColor(1, 1, 1, ICON_A)
                end
                CUI.HideWidgetTooltip()
            end)
            button:SetScript("OnClick", function()
                CUI.HideWidgetTooltip()
                onClick(button)
            end)
            button._icon = iconTex
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
                DB().barLocked = widget._locked
                local iconCell = widget._lockBtn._icon
                if not mod.DMPaintHdrArt(iconCell, widget._locked and "locked" or "unlocked") then
                    iconCell:SetTexture(
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
            local curX = GetCursorPosition()
            local es = widget:GetEffectiveScale()
            widget:SetWidth(max(MIN_W, resizeStartW + (curX / es - resizeStartX)))
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
            local curX = GetCursorPosition()
            resizeStartX = curX / widget:GetEffectiveScale()
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
            DB().barWidth = floor(widget:GetWidth() + 0.5)
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
                DB().barPos = { x = l, y = t }
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
            local maxS = max(0, #_history - (widget._visSlots or 1))
            _barScroll = max(0, min(_barScroll - delta, maxS))
            RefreshBarWindow()
        end)
    end

    -- Apply styling (bg from spell history settings, header from DM settings;
    -- the classic header shade follows this window's own colour)
    mod.DMPaintWindowBg(_barWin._bg, historyCfg.bgR or 0, historyCfg.bgG or 0, historyCfg.bgB or 0, historyCfg.bgAlpha or 0.25, true)

    local hc = dmCfg.hdrBgColor
    local hR, hG, hB = hc and hc.r or 0x1B / 255, hc and hc.g or 0x1B / 255, hc and hc.b or 0x1B / 255
    mod.DMPaintHeaderBg(
        _barWin._hdrBg,
        hR,
        hG,
        hB,
        dmCfg.hdrBgAlpha or 1,
        historyCfg.bgR or 0,
        historyCfg.bgG or 0,
        historyCfg.bgB or 0
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
    local hideTop = historyCfg.hideTopBar
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
    local maxBars = historyCfg.maxBars or 5
    local _, _, stride =
        mod._RowMetrics(historyCfg.shBarHeight or 18, dmCfg.barSpacing or 2, _barWin:GetEffectiveScale())
    local autoH = hdrH + maxBars * stride + ci * 2
    _barWin:SetSize(historyCfg.barWidth or 300, autoH)
    _barWin._locked = historyCfg.barLocked or false
    local place = historyCfg.barPos
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
    local historyCfg = DB()
    local barH, barSp, stride =
        mod._RowMetrics(historyCfg.shBarHeight or 18, dmCfg.barSpacing or 2, _barWin:GetEffectiveScale())
    local texPath = GetBarTexturePath()
    local fontSize = historyCfg.textSize or 11
    local contentFrame = _barWin._content
    local frameH = contentFrame:GetHeight()
    local visibleSlots = max(1, floor(frameH / stride + 0.5))
    _barWin._visSlots = visibleSlots

    -- Text color from spell history settings
    local txR, txG, txB
    if historyCfg.textColorUseAccent then
        txR, txG, txB = GetAccentRGB()
    else
        local tc = historyCfg.textColor
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
    local barAlpha = historyCfg.barOpacity or 1
    local stR, stG, stB = CLR_STOPPED[1], CLR_STOPPED[2], CLR_STOPPED[3]

    local sum = min(#_history, historyCfg.maxBars or 5)
    local loopEnd = max(visibleSlots, _lastBarVisible)
    local barIconZoom = historyCfg.iconZoom or 0.08

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
        if i <= visibleSlots and position <= sum then
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
            local statusText = record.status
            if barFrame._cachedStatus ~= statusText then
                barFrame._cachedStatus = statusText
                local cr, cg, callback
                if statusText == "failed" or statusText == "interrupted" then
                    cr, cg, callback = stR, stG, stB
                else
                    cr, cg, callback = nR, nG, nB
                end
                barFrame.fill:SetStatusBarColor(cr, cg, callback, barAlpha)
            end

            -- Fill value: always set for active casts, once for finished
            if record.fillProgress then
                barFrame.fill:SetValue(record.fillProgress)
            elseif statusText == "casting" or statusText == "channeling" then
                local nowTime = GetTime()
                local dur = record.endTime - record.startTime
                if dur > 0 then
                    local progress = statusText == "channeling" and (record.endTime - nowTime) / dur
                        or (nowTime - record.startTime) / dur
                    barFrame.fill:SetValue(min(max(progress, 0), 1))
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
    _lastBarVisible = visibleSlots
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
    local visibleSlots = _barWin._visSlots or 5
    local scroll = _barScroll or 0
    for i = 1, min(visibleSlots, BAR_POOL_SIZE) do
        local position = scroll + i
        local record = _history[position]
        if not record then
            break
        end
        local statusText = record.status
        if statusText == "casting" or statusText == "channeling" then
            local barFrame = _barPool[i]
            if barFrame and barFrame.row:IsShown() then
                local dur = record.endTime - record.startTime
                if dur > 0 then
                    local progress = statusText == "channeling" and (record.endTime - nowTime) / dur
                        or (nowTime - record.startTime) / dur
                    barFrame.fill:SetValue(min(max(progress, 0), 1))
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
    local historyCfg = DB()
    local isActive = historyCfg.iconEnabled or historyCfg.barEnabled

    -- Dynamic event registration: zero overhead when disabled
    if isActive then
        RegisterEvents()
    else
        UnregisterEvents()
        StopCastAnim()
    end

    if historyCfg.iconEnabled then
        BuildIconStrip()
    elseif _iconContainer then
        _iconContainer:Hide()
    end

    if historyCfg.barEnabled then
        BuildBarWindow()
    elseif _barWin then
        _barWin:Hide()
    end

    -- Keep disabled cost at zero: only subscribe to unlock transitions while
    -- Icon History itself is enabled.
    if historyCfg.iconEnabled and not mod._iconUnlockListenerRegistered and CUI.RegisterUnlockModeListener then
        mod._iconUnlockListenerRegistered = true
        CUI:RegisterUnlockModeListener("EDM_IconHistory", function()
            if DB().iconEnabled then
                BuildIconStrip()
            end
        end)
    elseif not historyCfg.iconEnabled and mod._iconUnlockListenerRegistered and CUI.UnregisterUnlockModeListener then
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
