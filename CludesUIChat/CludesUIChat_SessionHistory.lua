if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIChat_SessionHistory.lua
--
--  Persists recent player chat across /reload and relog. Lines are captured
--  from the display engine's bridge tail: the FINAL formatted string
--  (player links, class colors, channel prefix included), after Blizzard's
--  secure pipeline produced it. Capture happens in the open world only and
--  never stores secret values; restore replays into both message surfaces
--  through the engine, so replayed lines keep working links and stay inside
--  the range the wheel scrolls. Saved format is compatible with the
--  previous sessionLog schema (message body without timestamp prefix;
--  the prefix is re-applied on restore from serverTime with the current
--  timestamp format).
-------------------------------------------------------------------------------
local _, mod = ...
local CHAT = mod.ECHAT
if not CHAT then
    return
end

local strsub = string.sub
local wipe = wipe
local GetTime = GetTime
local GetServerTime = GetServerTime
local pcall = pcall
local date = date

local SV_NAME = "CludesUIChatScrollDB"
local MAX_TEXT_LEN = 4096
local RESTORE_DELAY_SEC = 2.0
local RESTORE_RETRY_SEC = 2.0
local RESTORE_MAX_ATTEMPTS = 3
-- Capture starts RESTORE_DELAY + this many seconds after login/reload (avoids login spam).
local SESSION_EPOCH_DELAY_SEC = 3.0

local observerInstalled = false
local restoreToken = 0
local restoredFrames = {}
local sessionEpochTime = nil
local captureSeq = 0

local eventFrame = CreateFrame("Frame")
local deferFrame = CreateFrame("Frame")
local UnarmDeferredRestore

-- Player-chat events worth persisting; system/loot/combat spam is not.
local CAPTURE_EVENTS = {
    CHAT_MSG_SAY = true,
    CHAT_MSG_YELL = true,
    CHAT_MSG_EMOTE = true,
    CHAT_MSG_TEXT_EMOTE = true,
    CHAT_MSG_PARTY = true,
    CHAT_MSG_PARTY_LEADER = true,
    CHAT_MSG_GUILD = true,
    CHAT_MSG_OFFICER = true,
    CHAT_MSG_CHANNEL = true,
    CHAT_MSG_RAID = true,
    CHAT_MSG_RAID_LEADER = true,
    CHAT_MSG_RAID_WARNING = true,
    CHAT_MSG_WHISPER = true,
    CHAT_MSG_WHISPER_INFORM = true,
    CHAT_MSG_BN_WHISPER = true,
    CHAT_MSG_BN_WHISPER_INFORM = true,
}

-------------------------------------------------------------------------------
--  Helpers
-------------------------------------------------------------------------------
local function PersistEnabled()
    if not CHAT.DB then
        return false
    end
    local saved = CHAT.DB()
    if not saved then
        return false
    end
    return saved.persistChatHistory == true
end

local function SessionHistorySafe()
    if not PersistEnabled() then
        return false
    end
    if CludesUI.InProtectedInstance() then
        return false
    end
    if GetCVarBool and GetCVarBool("addonChatRestrictionsForced") then
        return false
    end
    return true
end

local function InOpenWorld()
    -- Housing plots register as "scenario" but chat is unrestricted there
    if C_Housing and C_Housing.IsInsideHouseOrPlot and C_Housing.IsInsideHouseOrPlot() then
        return true
    end
    local inInstance, instanceType = IsInInstance()
    if not inInstance then
        return true
    end
    return instanceType == "none" or instanceType == ""
end

local function CaptureAllowed()
    if not PersistEnabled() then
        return false
    end
    if GetCVarBool and GetCVarBool("addonChatRestrictionsForced") then
        return false
    end
    if not InOpenWorld() then
        return false
    end
    return true
end

local function MaxLines()
    local maxN = 100
    if CHAT.DB then
        local saved = CHAT.DB()
        if saved and saved.persistChatHistoryMaxLines then
            maxN = saved.persistChatHistoryMaxLines
        end
    end
    if maxN < 10 then
        maxN = 10
    end
    if maxN > 500 then
        maxN = 500
    end
    return maxN
end

local function MarkSessionEpoch()
    sessionEpochTime = GetTime()
end

local function IsCombatLogChatFrame(castFrame)
    if not castFrame then
        return false
    end
    local combat = _G.COMBATLOG
    if combat and castFrame == combat then
        return true
    end
    local func = _G.IsCombatLog
    if type(func) == "function" then
        local success, region = pcall(func, castFrame)
        if success and region then
            return true
        end
    end
    return false
end

local function ShouldTrackFrame(castFrame)
    if not castFrame or not castFrame.GetName then
        return false
    end
    if castFrame.isTemporary then
        return false
    end
    local name = castFrame:GetName()
    if not name or not name:match("^ChatFrame%d+$") then
        return false
    end
    return not IsCombatLogChatFrame(castFrame)
end

local function GetSV()
    local savedVars = _G[SV_NAME]
    if type(savedVars) ~= "table" then
        savedVars = { sessionLog = {} }
        _G[SV_NAME] = savedVars
    end
    if type(savedVars.sessionLog) ~= "table" then
        savedVars.sessionLog = {}
    end
    if savedVars.byFrame then
        savedVars.byFrame = nil
    end
    return savedVars
end

local function IsValidMessage(message)
    if message == nil then
        return false
    end
    if issecretvalue and issecretvalue(message) then
        return false
    end
    local success, valid = pcall(function()
        return type(message) == "string" and message ~= ""
    end)
    return success and valid
end

local function MessageForStorage(message)
    if not IsValidMessage(message) then
        return nil
    end
    local success, stored = pcall(function()
        if #message > MAX_TEXT_LEN then
            return strsub(message, 1, MAX_TEXT_LEN)
        end
        return message
    end)
    if success then
        return stored
    end
    return nil
end

-- Strip the timestamp Blizzard's formatter baked into the line (our
-- timestampFormat rides the showTimestamps CVar, so captured lines carry it).
-- Also cleans legacy saves that stored the prefix. The prefix is re-applied
-- on restore from serverTime with whatever format is current.
-- Matches: "12:34 ...", "12:34:56 ...", "1:23 AM ...", "12:34:56 PM ..."
local function StripTimestampPrefix(message)
    if type(message) ~= "string" then
        return message
    end
    local rest = message:match("^%d%d?:%d%d:%d%d%s*[AP]M%s+(.+)$")
        or message:match("^%d%d?:%d%d:%d%d%s+(.+)$")
        or message:match("^%d%d?:%d%d%s*[AP]M%s+(.+)$")
        or message:match("^%d%d?:%d%d%s+(.+)$")
    if rest and rest ~= "" then
        return rest
    end
    return message
end

local function TimestampFormatFromDB()
    if not CHAT.DB then
        return nil
    end
    local saved = CHAT.DB()
    local fmt = saved and saved.timestampFormat
    if fmt == "none" or fmt == "__blizzard" then
        return nil
    end
    if type(fmt) == "string" and fmt ~= "" then
        return fmt
    end
    return nil
end

local function EffectiveTimestampFormat()
    local fmt = TimestampFormatFromDB()
    if fmt then
        return fmt
    end
    if ChatFrameUtil and ChatFrameUtil.GetTimestampFormat then
        local success, frame = pcall(ChatFrameUtil.GetTimestampFormat)
        if success and frame then
            return frame
        end
    end
    if GetCVar then
        local cvar = GetCVar("showTimestamps")
        if cvar and cvar ~= "" and cvar ~= "none" then
            return cvar
        end
    end
    return nil
end

local function FormatTimestampPrefix(serverTime)
    local fmt = EffectiveTimestampFormat()
    if not fmt or not serverTime or not date then
        return ""
    end
    local success, ts = pcall(date, fmt, serverTime)
    if success and type(ts) == "string" and ts ~= "" then
        return ts
    end
    return ""
end

local function RestoreDisplayMessage(record)
    local body = MessageForStorage(record and record.message)
    if not body then
        return nil
    end
    body = StripTimestampPrefix(body)
    local prefixText = FormatTimestampPrefix(record.serverTime)
    if prefixText ~= "" then
        return prefixText .. body
    end
    return body
end

local function NormalizeForDedup(message)
    local textValue = StripTimestampPrefix(message)
    if not textValue then
        return nil
    end
    textValue = textValue:gsub("|H.-|h(.-)|h", "%1")
    textValue = textValue:gsub("|c%x%x%x%x%x%x%x%x", "")
    textValue = textValue:gsub("|r", "")
    return textValue
end

local TrimLinesToMax = function(lines, maxN)
    local num = #lines
    if num <= maxN then
        return lines
    end
    local result = {}
    local start = num - maxN + 1
    for index = start, num do
        result[#result + 1] = lines[index]
    end
    return result
end

local function SortLinesChronological(lines)
    table.sort(lines, function(a, b)
        local ta = a.serverTime or a.timestamp or 0
        local tb = b.serverTime or b.timestamp or 0
        if ta ~= tb then
            return ta < tb
        end
        return (a.captureSeq or 0) < (b.captureSeq or 0)
    end)
    return lines
end

local function SanitizeLineList(lines)
    if type(lines) ~= "table" then
        return nil
    end
    local result = {}
    for _, L in ipairs(lines) do
        if type(L) == "table" then
            local message = MessageForStorage(L.message)
            if message then
                message = StripTimestampPrefix(message)
            end
            -- Legacy stored lines can carry |K protected-name tokens from a
            -- DEAD session's mapping (captured before the capture-side
            -- substitution existed): unrecoverable and wrongly attributed on
            -- replay, so they are dropped -- this heals poisoned stores on
            -- the first sanitize after update.
            if message and message:find("|K", 1, true) then
                message = nil
            end
            if message then
                result[#result + 1] = {
                    message = message,
                    event = L.event,
                    r = (type(L.r) == "number" and L.r) or 1,
                    g = (type(L.g) == "number" and L.g) or 1,
                    b = (type(L.b) == "number" and L.b) or 1,
                    id = (type(L.id) == "number" and L.id) or 1,
                    timestamp = (type(L.timestamp) == "number" and L.timestamp) or GetTime(),
                    serverTime = (type(L.serverTime) == "number" and L.serverTime) or GetServerTime(),
                    captureSeq = (type(L.captureSeq) == "number" and L.captureSeq) or nil,
                }
            end
        end
    end
    return TrimLinesToMax(result, MaxLines())
end

local function SanitizeSV()
    local savedVars = GetSV()
    local cleaned = SanitizeLineList(savedVars.sessionLog)
    if cleaned and #cleaned > 0 then
        savedVars.sessionLog = cleaned
    else
        savedVars.sessionLog = {}
    end
end

local function FrameShowsEvent(castFrame, evt)
    if not castFrame or not evt then
        return false
    end
    local chatType = gsub(strsub(evt, 10), "_INFORM", "")
    local entries = castFrame.messageTypeList
    if type(entries) ~= "table" then
        return true
    end
    for index = 1, #entries do
        if entries[index] == chatType then
            return true
        end
    end
    return false
end

local function AppendLogEntry(record)
    local savedVars = GetSV()
    local log = savedVars.sessionLog
    local norm = NormalizeForDedup(record.message)
    if norm then
        -- The bridge tail fires once per window that displays the line, so
        -- the same message can arrive more than once back to back.
        local checkN = math.min(#log, 10)
        for index = #log, #log - checkN + 1, -1 do
            if NormalizeForDedup(log[index].message) == norm then
                return
            end
        end
    end
    log[#log + 1] = record
    savedVars.sessionLog = TrimLinesToMax(log, MaxLines())
end

-------------------------------------------------------------------------------
--  Capture: the engine's bridge tail hands us the final formatted line for
--  every message our windows display. Everything here runs in our own
--  execution (the tail is the last step after Blizzard's pipeline finished);
--  secret lines never pass IsValidMessage.
-------------------------------------------------------------------------------

-- Battle.net display names arrive as |K..|k protected-name tokens, resolved by
-- the CLIENT from a SESSION-SCOPED table at render time. Persisting a token
-- and replaying it next session resolves it against the new session's table --
-- the line renders under whichever friend now holds that id (field report
-- 2026-08-16: a whole BN whisper conversation attributed to the wrong friend
-- after an update's relaunch). Capture therefore substitutes each token with
-- the friend's literal BattleTag (stable across sessions): a friend's
-- accountName IS their token string this session, so plain string equality
-- maps token -> tag, and tokens are escaped for literal gsub so the exact
-- token format never matters. Returns nil when any token is left unresolved
-- (friend removed mid-session, non-friend token) -- wrong attribution is
-- worse than a missing line, so such lines are never stored.
local function ResolveBNetTokens(textValue)
    if not textValue:find("|K", 1, true) then
        return textValue
    end
    local map
    local numFriends = BNGetNumFriends and BNGetNumFriends()
    if numFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
        for index = 1, numFriends do
            local acc = C_BattleNet.GetFriendAccountInfo(index)
            local tokenName = acc and acc.accountName
            local tag = acc and acc.battleTag
            if
                tokenName ~= nil
                and not (issecretvalue and issecretvalue(tokenName))
                and type(tokenName) == "string"
                and tokenName:find("|K", 1, true)
                and tag ~= nil
                and not (issecretvalue and issecretvalue(tag))
                and type(tag) == "string"
                and tag ~= ""
            then
                map = map or {}
                map[tokenName] = tag
            end
        end
    end
    if map then
        for token, tag in pairs(map) do
            textValue = textValue:gsub(token:gsub("(%W)", "%%%1"), tag)
        end
    end
    if textValue:find("|K", 1, true) then
        return nil
    end
    return textValue
end

local function OnBridgeLine(castFrame, message, region, g, b, chatTypeID, evt)
    if not evt or not CAPTURE_EVENTS[evt] then
        return
    end
    if not sessionEpochTime or GetTime() < sessionEpochTime then
        return
    end
    if not CaptureAllowed() then
        return
    end
    if not ShouldTrackFrame(castFrame) then
        return
    end

    local body = MessageForStorage(message)
    if not body then
        return
    end
    body = StripTimestampPrefix(body)
    if body == "" then
        return
    end
    body = ResolveBNetTokens(body)
    if not body then
        return
    end

    captureSeq = captureSeq + 1
    AppendLogEntry({
        event = evt,
        message = body,
        r = (type(region) == "number" and region) or 1,
        g = (type(g) == "number" and g) or 1,
        b = (type(b) == "number" and b) or 1,
        id = (type(chatTypeID) == "number" and chatTypeID) or 1,
        timestamp = GetTime(),
        serverTime = GetServerTime(),
        captureSeq = captureSeq,
    })
end

local function InstallCapture()
    if observerInstalled then
        return
    end
    if not CHAT.EngineSetTailObserver then
        return
    end
    observerInstalled = true
    CHAT.EngineSetTailObserver(OnBridgeLine)
end

local function UninstallCapture()
    if not observerInstalled then
        return
    end
    observerInstalled = false
    if CHAT.EngineSetTailObserver then
        CHAT.EngineSetTailObserver(nil)
    end
end

local function ClearSavedSessionHistory()
    restoreToken = restoreToken + 1
    wipe(restoredFrames)
    captureSeq = 0
    sessionEpochTime = nil
    UnarmDeferredRestore()
    GetSV().sessionLog = {}
end

function CHAT.SnapshotChatSessionHistory()
    if not PersistEnabled() then
        return
    end
    SanitizeSV()
end

-------------------------------------------------------------------------------
--  Restore: replay saved lines through the engine's backfill (oldest lines
--  end up above everything already displayed).
-------------------------------------------------------------------------------
UnarmDeferredRestore = function()
    deferFrame:UnregisterAllEvents()
    deferFrame:SetScript("OnEvent", nil)
end

-- Normalized hashes of what a window already shows, so relog restores do not
-- duplicate lines that survived in the engine (O(n) once per window).
local function BuildWindowMessageSet(castFrame)
    local set = {}
    if not CHAT.EngineGetMessageLines then
        return set
    end
    local raw = {}
    CHAT.EngineGetMessageLines(castFrame, raw)
    for index = 1, #raw do
        local stored = MessageForStorage(raw[index])
        if stored then
            local success, norm = pcall(NormalizeForDedup, stored)
            if success and norm then
                set[norm] = true
            end
        end
    end
    return set
end

local function RestoreWindow(castFrame, frameName, log)
    if not castFrame or not log or #log == 0 then
        return false
    end
    if not ShouldTrackFrame(castFrame) then
        return false
    end
    if restoredFrames[frameName] then
        return false
    end
    if not (mod._chatWins and mod._chatWins[castFrame]) then
        return false
    end

    local lines = SanitizeLineList(log)
    if not lines or #lines == 0 then
        return false
    end
    lines = SortLinesChronological(lines)

    local existingSet = BuildWindowMessageSet(castFrame)

    local pushed = 0
    -- Newest first: each BackFill lands above the previous push, so the final
    -- on-screen order is chronological, above whatever login produced.
    for index = #lines, 1, -1 do
        local record = lines[index]
        if record and record.event and record.message and FrameShowsEvent(castFrame, record.event) then
            local norm = NormalizeForDedup(record.message)
            if not (norm and existingSet[norm]) then
                local textValue = RestoreDisplayMessage(record)
                if
                    textValue
                    and CHAT.EngineBackfillLine(castFrame, textValue, record.r, record.g, record.b, record.id)
                then
                    pushed = pushed + 1
                end
            end
        end
    end

    if pushed == 0 then
        return false
    end

    restoredFrames[frameName] = true
    return true
end

local function RunRestore(token)
    if token ~= restoreToken then
        return
    end
    if not SessionHistorySafe() then
        return false
    end

    local log = GetSV().sessionLog
    if not log or #log == 0 then
        return false
    end

    local any = false
    for index = 1, 10 do
        local name = "ChatFrame" .. index
        local castFrame = _G[name]
        if castFrame and RestoreWindow(castFrame, name, log) then
            any = true
        end
    end
    return any
end

local TryRestore -- forward declaration (mutually recursive with ArmDeferredRestore)

local function ArmDeferredRestore(token)
    UnarmDeferredRestore()
    local function onDefer(_, deferEvent, ...)
        if token ~= restoreToken then
            UnarmDeferredRestore()
            return
        end
        if deferEvent == "PLAYER_ENTERING_WORLD" then
            local _, isReloadingUi = ...
            if isReloadingUi then
                return
            end
        end
        if not SessionHistorySafe() then
            return
        end
        UnarmDeferredRestore()
        TryRestore(token, 1)
    end
    deferFrame:SetScript("OnEvent", onDefer)
    deferFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    deferFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    if C_ChallengeMode then
        deferFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    end
end

TryRestore = function(token, attempt)
    if token ~= restoreToken then
        return
    end
    if not PersistEnabled() then
        return
    end
    if not SessionHistorySafe() then
        ArmDeferredRestore(token)
        return
    end

    attempt = attempt or 1
    local log = GetSV().sessionLog
    local hasLog = log and #log > 0
    local restored = RunRestore(token)

    if hasLog and not restored and attempt < RESTORE_MAX_ATTEMPTS then
        wipe(restoredFrames)
        C_Timer.After(RESTORE_RETRY_SEC, function()
            TryRestore(token, attempt + 1)
        end)
    end
end

function CHAT.RestoreChatSessionHistory()
    UnarmDeferredRestore()
    restoreToken = restoreToken + 1
    wipe(restoredFrames)
    local token = restoreToken
    if not PersistEnabled() then
        return
    end
    C_Timer.After(RESTORE_DELAY_SEC, function()
        TryRestore(token, 1)
    end)
end

function CHAT.OnSessionHistoryToggled(enabled)
    if enabled then
        CHAT.InitChatSessionHistory()
        CHAT.RestoreChatSessionHistory()
    else
        UninstallCapture()
        ClearSavedSessionHistory()
    end
end

local function ScheduleSessionEpochAfterLogin()
    C_Timer.After(RESTORE_DELAY_SEC + SESSION_EPOCH_DELAY_SEC, MarkSessionEpoch)
end

function CHAT.InitChatSessionHistory()
    if not PersistEnabled() then
        UninstallCapture()
        ClearSavedSessionHistory()
        return
    end
    SanitizeSV()
    InstallCapture()
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("PLAYER_LEAVING_WORLD")

eventFrame:SetScript("OnEvent", function(_, evt, ...)
    if evt == "PLAYER_LOGOUT" or evt == "PLAYER_LEAVING_WORLD" then
        if PersistEnabled() then
            CHAT.SnapshotChatSessionHistory()
        else
            ClearSavedSessionHistory()
        end
        return
    end

    if evt == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        if not isInitialLogin and not isReloadingUi then
            if SessionHistorySafe() then
                CHAT.RestoreChatSessionHistory()
            end
            return
        end
        sessionEpochTime = nil
        captureSeq = 0
        CHAT.InitChatSessionHistory()
        if PersistEnabled() then
            CHAT.RestoreChatSessionHistory()
            ScheduleSessionEpochAfterLogin()
        end
    end
end)
