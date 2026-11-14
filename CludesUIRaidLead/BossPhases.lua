if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  BossPhases.lua -- Raid Lead: when each Midnight raid boss changes phase.
--
--  Under 12.1 the combat log is closed, so a phase change is read from the
--  boss's own timeline (ENCOUNTER_TIMELINE_EVENT_ADDED and its durations:
--  a new phase adds its first timers together) or from a boss's casts. Each
--  boss has its own rule here. On a change, fight:StartReminders(phase)
--  restarts the bars and alerts from that phase (BossTimeline.lua).
--
--  self is the fight (BossTimeline.lua): Phase, PhaseSwapTime, EncounterID,
--  Timelines, RemovedTimelines, DifficultyCheck, StartReminders,
--  DelayAllReminders, EncounterRegister, EncounterFunction and
--  GetActiveEncounterTimelineEventCount.
-------------------------------------------------------------------------------
local _, ns = ...

local function Near(a, b, by)
    if ApproximatelyEqual then
        return ApproximatelyEqual(a, b, by)
    end
    return math.abs(a - b) <= by
end

local P = {}
ns.BossPhases = P

local function NextPhase(num)
    return num + 1
end

-------------------------------------------------------------------------------
--  Belo'ren (3182): Death Drop's 6 second timer starts each new phase.
-------------------------------------------------------------------------------
do
    local detectedDurations = {
        [14] = { { time = 6, phase = NextPhase } },
        [15] = { { time = 6, phase = NextPhase } },
        [16] = { { time = 6, phase = NextPhase } },
    }
    P[3182] = {
        detect = function(self, e, info)
            local now = GetTime()
            if
                e == "ENCOUNTER_TIMELINE_EVENT_REMOVED"
                or not info
                or not self.PhaseSwapTime
                or not (now > self.PhaseSwapTime + 5)
                or not self.EncounterID
                or not self.Phase
            then
                return
            end
            local difficultyID = self:DifficultyCheck({ 14, 15, 16, 233 })
            if not difficultyID or not detectedDurations[difficultyID] then
                return
            end
            table.insert(self.Timelines, now)
            if self.Phase >= 2 and Near(info.duration, 40, 0.2) then
                local diff = now - self.PhaseSwapTime
                local offset = diff - 7.1
                if diff <= 20 and offset > 0.3 then -- the bird landed late: every timer moves with it
                    self:DelayAllReminders(offset)
                end
            end
            for _, phaseinfo in ipairs(detectedDurations[difficultyID]) do
                if info.duration == phaseinfo.time then
                    local count = 0
                    for _, v in ipairs(self.Timelines) do
                        if now < v + 0.1 then
                            count = count + 1
                        end
                    end
                    local newphase = phaseinfo.phase(self.Phase)
                    if newphase > self.Phase and count <= 1 then
                        self.Phase = newphase
                        self:StartReminders(self.Phase)
                        self.PhaseSwapTime = now
                        break
                    end
                end
            end
        end,
    }
end

-------------------------------------------------------------------------------
--  Chimaerus (3306): a long timer marks the next phase.
-------------------------------------------------------------------------------
do
    local detectedDurations = {
        [14] = { { time = 164.5, phase = NextPhase } },
        [15] = { { time = 151.36, phase = NextPhase } },
        [16] = { { time = 120, phase = NextPhase } },
    }
    P[3306] = {
        detect = function(self, e, info)
            local now = GetTime()
            if
                e == "ENCOUNTER_TIMELINE_EVENT_REMOVED"
                or not info
                or not self.PhaseSwapTime
                or not (now > self.PhaseSwapTime + 5)
                or not self.EncounterID
                or not self.Phase
            then
                return
            end
            local difficultyID = self:DifficultyCheck({ 14, 15, 16 })
            if (not difficultyID) or not detectedDurations[difficultyID] then
                return
            end
            local phaseinfo = detectedDurations[difficultyID][1]
            if phaseinfo and info.duration >= phaseinfo.time then
                local newphase = phaseinfo.phase(self.Phase)
                if newphase > self.Phase then
                    self.Phase = newphase
                    self:StartReminders(self.Phase)
                    self.PhaseSwapTime = now
                end
            end
        end,
    }
end

-------------------------------------------------------------------------------
--  Crown of the Cosmos (3181): each phase's timer, and on Mythic how many
--  timers arrive together.
-------------------------------------------------------------------------------
do
    local detectedDurations = {
        [14] = {
            {
                time = 1.5,
                phase = function()
                    return 2
                end,
            },
            {
                time = 24,
                phase = function()
                    return 3
                end,
            },
            {
                time = 1.5,
                phase = function()
                    return 4
                end,
            },
            {
                time = 60,
                phase = function()
                    return 5
                end,
            },
        },
        [15] = {
            {
                time = 1.5,
                phase = function()
                    return 2
                end,
            },
            {
                time = 24,
                phase = function()
                    return 3
                end,
            },
            {
                time = 1.5,
                phase = function()
                    return 4
                end,
            },
            {
                time = 60,
                phase = function()
                    return 5
                end,
            },
        },
    }
    local RequiredTimers = { 2, 4, false, 4 }

    local function MythicPhaseDetect(self, e, info)
        local now = GetTime()
        if (not info) or not self.PhaseSwapTime or not (now > self.PhaseSwapTime + 5) then
            return
        end
        if e == "ENCOUNTER_TIMELINE_EVENT_REMOVED" then
            table.insert(self.RemovedTimelines, now)
        else
            if
                self.Phase >= 2
                or (self.Phase == 1 and (info.duration == 1.5 or info.duration == 25 or info.duration == 6))
            then
                table.insert(self.Timelines, now)
            end
        end
        local addedcount = 0
        for _, v in ipairs(self.Timelines) do
            if now < v + 0.3 then
                addedcount = addedcount + 1
            end
        end
        if self.Phase ~= 3 and RequiredTimers[self.Phase] and addedcount >= RequiredTimers[self.Phase] then
            self.Phase = self.Phase + 1
            self:StartReminders(self.Phase)
            self.Timelines = {}
            self.RemovedTimelines = {}
            self.PhaseSwapTime = now
            return
        end
        if
            self.Phase == 3
            and (addedcount >= 8 or (e == "ENCOUNTER_TIMELINE_EVENT_ADDED" and info.duration == 60))
        then
            self.Phase = 5
            self:StartReminders(self.Phase)
            self.Timelines = {}
            self.RemovedTimelines = {}
            self.PhaseSwapTime = now
        end
    end

    P[3181] = {
        detect = function(self, e, info)
            local now = GetTime()
            local difficultyID = self:DifficultyCheck({ 14, 15, 16 })
            if difficultyID and difficultyID == 16 then
                MythicPhaseDetect(self, e, info)
                return
            end
            if
                e == "ENCOUNTER_TIMELINE_EVENT_REMOVED"
                or not info
                or not self.PhaseSwapTime
                or not (now > self.PhaseSwapTime + 5)
                or not self.EncounterID
                or not self.Phase
            then
                return
            end
            if (not difficultyID) or not detectedDurations[difficultyID] then
                return
            end
            local phaseinfo = detectedDurations[difficultyID][self.Phase]
            if phaseinfo and info.duration == phaseinfo.time then
                local newphase = phaseinfo.phase(self.Phase)
                if newphase > self.Phase then
                    self.Phase = newphase
                    self:StartReminders(self.Phase)
                    self.PhaseSwapTime = now
                end
            end
        end,
    }
end

-------------------------------------------------------------------------------
--  Midnight Falls (3183): each phase's timer, and the last phase once the
--  second boss is gone.
-------------------------------------------------------------------------------
do
    local detectedDurations = {
        [15] = {
            {
                time = 45,
                phase = function()
                    return 2
                end,
            },
            {
                time = 97,
                phase = function()
                    return 3
                end,
            },
            {
                time = 180,
                phase = function()
                    return 4
                end,
            },
        },
        [16] = {
            {
                time = 45,
                phase = function()
                    return 2
                end,
            },
            {
                time = 97,
                phase = function()
                    return 3
                end,
            },
            {
                time = 180,
                phase = function()
                    return 4
                end,
            },
        },
    }
    P[3183] = {
        engage = true,
        detect = function(self, e, info)
            local now = GetTime()
            if e == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" and self.Phase == 4 then
                if (not self.PhaseSwapTime) or not (now > self.PhaseSwapTime + 20) then
                    return
                end
                if not UnitExists("boss2") then
                    self.Phase = 5
                    self:StartReminders(self.Phase)
                    self.PhaseSwapTime = GetTime()
                end
                return
            end
            if
                e == "ENCOUNTER_TIMELINE_EVENT_REMOVED"
                or not info
                or not self.PhaseSwapTime
                or not (now > self.PhaseSwapTime + 5)
                or not self.EncounterID
                or not self.Phase
            then
                return
            end
            local difficultyID = self:DifficultyCheck({ 14, 15, 16 })
            if (not difficultyID) or not detectedDurations[difficultyID] then
                return
            end
            local phaseinfo = detectedDurations[difficultyID][self.Phase]
            if phaseinfo and Near(info.duration, phaseinfo.time, 0.2) then
                local newphase = phaseinfo.phase(self.Phase)
                if newphase > self.Phase then
                    self.Phase = newphase
                    self:StartReminders(self.Phase)
                    self.PhaseSwapTime = now
                end
            end
        end,
    }
end

-------------------------------------------------------------------------------
--  Vaelgor & Ezzorak (3178): an 8 second timer, then the phase 8 seconds on.
-------------------------------------------------------------------------------
do
    local detectedDurations = {
        [14] = { {
            time = 8,
            phase = function()
                return 2
            end,
        } },
        [15] = { {
            time = 8,
            phase = function()
                return 2
            end,
        } },
    }
    P[3178] = {
        detect = function(self, e, info)
            local now = GetTime()
            if
                e == "ENCOUNTER_TIMELINE_EVENT_REMOVED"
                or not info
                or not self.PhaseSwapTime
                or not (now > self.PhaseSwapTime + 5)
                or not self.EncounterID
                or not self.Phase
            then
                return
            end
            local difficultyID = self:DifficultyCheck({ 14, 15, 16 })
            local phaseinfo = difficultyID
                and detectedDurations[difficultyID]
                and detectedDurations[difficultyID][self.Phase]
            if phaseinfo and info.duration == phaseinfo.time then
                if self.VaelgorPhaseTimer then
                    self.VaelgorPhaseTimer:Cancel()
                end
                self.VaelgorPhaseTimer = C_Timer.NewTimer(8, function()
                    if not self.EncounterID then
                        return
                    end
                    local newphase = phaseinfo.phase(self.Phase)
                    if newphase > self.Phase then
                        self.Phase = newphase
                        self:StartReminders(self.Phase)
                        self.PhaseSwapTime = now
                    end
                end)
            end
        end,
    }
end

-------------------------------------------------------------------------------
--  Entombed Sentinels (3445): eight timers at once start the next phase.
-------------------------------------------------------------------------------
P[3445] = {
    detect = function(self, e, info)
        local now = GetTime()
        if
            e ~= "ENCOUNTER_TIMELINE_EVENT_ADDED"
            or not info
            or not self.PhaseSwapTime
            or not (now > self.PhaseSwapTime + 5)
            or not self.EncounterID
            or not self.Phase
        then
            return
        end
        table.insert(self.Timelines, now)
        local addedcount = 0
        for _, timestamp in ipairs(self.Timelines) do
            if now < timestamp + 0.3 then
                addedcount = addedcount + 1
            end
        end
        if addedcount >= 8 then
            self.Phase = self.Phase + 1
            self:StartReminders(self.Phase)
            self.Timelines = {}
            self.PhaseSwapTime = now
        end
    end,
}

-------------------------------------------------------------------------------
--  The Coiled Altar (3429): a 70 second timer for phase 2, the second boss's
--  channel with no timers up for 2.5, and four timers at once for 3.
-------------------------------------------------------------------------------
do
    local detectedDurations = {
        [14] = { [1] = {
            time = 70,
            phase = function()
                return 2
            end,
        } },
        [15] = { [1] = {
            time = 70,
            phase = function()
                return 2
            end,
        } },
        [16] = { [1] = {
            time = 70,
            phase = function()
                return 2
            end,
        } },
    }
    P[3429] = {
        start = function(self)
            self:EncounterRegister("CoiledAltarPhaseDetect", "UNIT_SPELLCAST_CHANNEL_START", true, "boss2")
            self:EncounterFunction("CoiledAltarPhaseDetect", function(_, e)
                local activeTimelineCount = self:GetActiveEncounterTimelineEventCount()
                if e ~= "UNIT_SPELLCAST_CHANNEL_START" or self.Phase ~= 2 or activeTimelineCount ~= 0 then
                    return
                end
                self.Phase = 2.5
                self:StartReminders(self.Phase)
                self.PhaseSwapTime = GetTime()
            end)
        end,
        detect = function(self, e, info)
            local now = GetTime()
            if
                e ~= "ENCOUNTER_TIMELINE_EVENT_ADDED"
                or not info
                or not self.PhaseSwapTime
                or not (now > self.PhaseSwapTime + 5)
                or not self.EncounterID
                or not self.Phase
            then
                return
            end
            local difficultyID = self:DifficultyCheck({ 14, 15, 16 })
            if (not difficultyID) or not detectedDurations[difficultyID] then
                return
            end
            if self.Phase == 2.5 then
                table.insert(self.Timelines, now)
                local addedcount = 0
                for _, timestamp in ipairs(self.Timelines) do
                    if now < timestamp + 0.3 then
                        addedcount = addedcount + 1
                    end
                end
                if addedcount < 4 then
                    return
                end
                self.Phase = 3
                self:StartReminders(self.Phase)
                self.PhaseSwapTime = now
                return
            end
            local phaseinfo = detectedDurations[difficultyID][self.Phase]
            if not phaseinfo then
                return
            end
            if Near(info.duration, phaseinfo.time, 0.2) then
                local newphase = phaseinfo.phase(self.Phase)
                if newphase <= self.Phase then
                    return
                end
                self.Phase = newphase
                self:StartReminders(self.Phase)
                self.PhaseSwapTime = now
            end
        end,
    }
end

-------------------------------------------------------------------------------
--  The Lost Explorers (3497): four timers at once, one of them 11, 13 or 16
--  seconds, at least 40 (then 100) seconds after the last change.
-------------------------------------------------------------------------------
P[3497] = {
    detect = function(self, e, info)
        local now = GetTime()
        local requiredDiff = self.Phase == 1 and 40 or 100
        if
            e ~= "ENCOUNTER_TIMELINE_EVENT_ADDED"
            or not info
            or not self.PhaseSwapTime
            or not (now > self.PhaseSwapTime + requiredDiff)
            or not self.EncounterID
            or not self.Phase
        then
            return
        end
        table.insert(self.Timelines, { timestamp = now, duration = info.duration })
        local addedcount = 0
        local hasRequiredDuration = false
        for _, timelineInfo in ipairs(self.Timelines) do
            if now < timelineInfo.timestamp + 0.3 then
                addedcount = addedcount + 1
                if
                    Near(timelineInfo.duration, 16, 0.2)
                    or Near(timelineInfo.duration, 11, 0.2)
                    or Near(timelineInfo.duration, 13, 0.2)
                then
                    hasRequiredDuration = true
                end
            end
        end
        if addedcount >= 4 and hasRequiredDuration then
            self.Phase = self.Phase + 1
            self:StartReminders(self.Phase)
            self.Timelines = {}
            self.PhaseSwapTime = now
        end
    end,
}

-------------------------------------------------------------------------------
--  Nek'zali the Soulcoiler (3470): read from the bosses' casts.
-------------------------------------------------------------------------------
P[3470] = {
    start = function(self)
        self.NekzaliBoss1SpellcastStartTimes = {}
        self.NekzaliBoss1ValidCastSequence = false
        self:EncounterRegister(
            "NekzaliPhaseDetect",
            { "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED" },
            true,
            "boss1"
        )
        self:EncounterFunction("NekzaliPhaseDetect", function(_, e)
            local now = GetTime()
            if e == "UNIT_SPELLCAST_START" and self.Phase == 1 then
                self.NekzaliBoss1SpellcastStartTimes[#self.NekzaliBoss1SpellcastStartTimes + 1] = now
                return
            end
            if e == "UNIT_SPELLCAST_SUCCEEDED" then
                for _, startTime in ipairs(self.NekzaliBoss1SpellcastStartTimes) do
                    if Near(now - startTime, 1.5, 0.2) then
                        self.NekzaliBoss1ValidCastSequence = true
                        break
                    end
                end
                return
            end
            local newPhase
            if e == "UNIT_SPELLCAST_CHANNEL_START" then
                if self.Phase == 1 then
                    if not self.NekzaliBoss1ValidCastSequence then
                        return
                    end
                    newPhase = 1.5
                elseif self.Phase == 1.75 then
                    newPhase = 2
                end
            elseif e == "UNIT_SPELLCAST_START" and self.Phase == 1.5 then
                if GetTime() - self.PhaseSwapTime < 25 then
                    return
                end
                if self:GetActiveEncounterTimelineEventCount() ~= 0 then
                    return
                end
                newPhase = 1.75
            else
                return
            end
            if not newPhase then
                return
            end
            self.Phase = newPhase
            if newPhase == 1.5 then
                self:EncounterRegister(
                    "NekzaliPhaseDetect",
                    { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED" },
                    false
                )
                self:EncounterRegister("NekzaliPhaseDetect", "UNIT_SPELLCAST_START", true, "boss2")
            elseif newPhase == 1.75 then
                self:EncounterRegister("NekzaliPhaseDetect", "UNIT_SPELLCAST_START", false)
            end
            self:StartReminders(self.Phase)
            self.PhaseSwapTime = GetTime()
        end)
    end,
}
