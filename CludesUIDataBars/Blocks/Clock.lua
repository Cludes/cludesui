if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Blocks\Clock.lua - Info Bar block: the clock.
--
--  Server or local time, 12 or 24 hour (both follow the game's own clock
--  settings until the block's settings pick), with a resting icon while
--  resting and a mail icon while mail waits. Hover shows the date, server
--  time, saved instances and the daily and weekly resets. Left-click opens the
--  calendar, right-click the game's clock, Shift+middle-click reloads.
--
--  It draws when what it shows changes: the minute, resting, mail. In combat
--  the bar is protected, so the text and icons change and the layout waits
--  for the end of combat.
--
--  Settings (blockCfg.settings): localTime, twentyFour (nil = the game's
--  setting); showResting, showMail (default on); fontSizeClock.
-------------------------------------------------------------------------------
local _, mod = ...
local L = mod.L
local K = mod.BlockKit

-- Kept as locals: the clock reads them every second.
local InCombatLockdown, date = InCombatLockdown, date
local format, floor, max, min = string.format, math.floor, math.max, math.min

-- Like the minimap clock: 24 hour padded (01:04), 12 hour not (1:04 PM).
local function ClockText(hour, minute, use24)
    if use24 then
        return format("%02d:%02d", hour, minute)
    end
    local suffix = hour >= 12 and "PM" or "AM"
    hour = hour % 12
    if hour == 0 then
        hour = 12
    end
    return format("%d:%02d %s", hour, minute, suffix)
end

local function RestSize()
    return floor(K.CONTENT_BASE * 0.5 + 0.5)
end

mod.BlockFactories.clock = function(blockCfg, slot, contentFrame, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = contentFrame, ctx = barCtx }
    inst.key = K.InstKey(barCtx, blockCfg)
    inst.events = {
        "PLAYER_UPDATE_RESTING",
        "PLAYER_REGEN_ENABLED",
        "MAIL_INBOX_UPDATE",
        "UPDATE_PENDING_MAIL",
    }
    local tickKey = "clock:" .. inst.key

    local function Settings()
        return blockCfg.settings or {}
    end

    -- A fixed size off CONTENT_BASE; the bar's height never scales the text.
    local function FontSize()
        return Settings().fontSizeClock or max(12, floor(K.CONTENT_BASE * 0.7333 + 0.5))
    end

    -- Unset toggles follow the game's clock settings, so this clock and the
    -- minimap's agree.
    local function Modes()
        local cfg = Settings()
        local useLocal, use24 = cfg.localTime, cfg.twentyFour
        if useLocal == nil then
            useLocal = GetCVar("timeMgrUseLocalTime") == "1"
        end
        if use24 == nil then
            use24 = GetCVar("timeMgrUseMilitaryTime") == "1"
        end
        return useLocal, use24
    end

    local function Now()
        local useLocal, use24 = Modes()
        if useLocal then
            return ClockText(tonumber(date("%H")), tonumber(date("%M")), use24)
        end
        local hour, minute = GetGameTime()
        return ClockText(floor(hour), floor(minute), use24)
    end

    local function ShowsRest()
        return Settings().showResting ~= false and IsResting()
    end
    local function ShowsMail()
        return Settings().showMail ~= false and HasNewMail()
    end

    local button = CreateFrame("Button", nil, contentFrame)
    button:SetSize(100, 20)
    button:SetPoint("CENTER")
    button:EnableMouse(true)
    button:RegisterForClicks("AnyUp")

    local label = button:CreateFontString(nil, "OVERLAY")
    K.AttachTextOffset(inst, label)
    label:SetPoint("CENTER")
    label:SetTextColor(1, 1, 1, 1)

    -- Resting: the player frame's rest animation, white, drawn 1.5x its
    -- frame (the art has wide margins), a little high, at 80% of the game's pace.
    local rest = CreateFrame("Frame", nil, contentFrame)
    rest:SetSize(16, 21)
    rest:Hide()
    local restArt = rest:CreateTexture(nil, "OVERLAY")
    restArt:SetDrawLayer("OVERLAY", 7)
    restArt:SetPoint("CENTER", rest, "CENTER", 0, 5)
    CludesUI.AddRestFlipbook(rest, restArt, 1.875)
    restArt:SetDesaturated(true)
    restArt:SetVertexColor(1, 1, 1, 1)

    -- Mail: left of the time while mail waits.
    local mailArt = button:CreateTexture(nil, "OVERLAY")
    mailArt:SetAtlas("Crosshair_mail_64")
    mailArt:Hide()

    local hovered = false
    local drawnTime -- the time on screen
    local drawnState -- time, rest and mail as last laid out
    local owesLayout = false -- something changed in combat

    local function State(timeText)
        return timeText .. (ShowsRest() and "|r" or "|-") .. (ShowsMail() and "|m" or "|-")
    end

    -- The text and the rest icon share one colour (the accent on hover).
    local function Paint()
        local red, green, blue
        if hovered then
            red, green, blue = mod.GetAccent()
        else
            red, green, blue = K.BlockColorOf(blockCfg)
        end
        label:SetTextColor(red, green, blue, 1)
        restArt:SetVertexColor(red, green, blue, 1)
    end

    function inst:Refresh()
        local timeText = Now()
        drawnTime = timeText
        -- In combat: the text, colour and icons only (none of them is
        -- protected); the layout waits for the end of combat.
        if InCombatLockdown() then
            owesLayout = true
            label:SetText(timeText)
            Paint()
            mailArt:SetShown(ShowsMail())
            rest:SetShown(ShowsRest())
            return
        end
        owesLayout = false
        drawnState = State(timeText)

        local fontSize = FontSize()
        local barH = barCtx.GetThickness()
        mod.SetFont(label, fontSize, barCtx.cfg)
        label:SetText(timeText)
        Paint()
        rest:SetShown(ShowsRest())
        mailArt:SetShown(ShowsMail())

        -- The rest frame is square; its art is drawn 1.5x around it.
        local restSize = RestSize()
        rest:SetSize(restSize, restSize)
        restArt:SetSize(floor(restSize * 1.5 + 0.5), floor(restSize * 1.5 + 0.5))
        rest:ClearAllPoints()
        local mailSize = restSize + 8
        mailArt:SetSize(mailSize, mailSize)
        mailArt:ClearAllPoints()

        if barCtx.IsVertical() then
            -- The time at the top of the slot; rest top right, mail top left.
            local slotW = K.VSlotW(inst)
            contentFrame:SetWidth(slotW)
            button:SetWidth(slotW)
            button:ClearAllPoints()
            button:SetPoint("CENTER", contentFrame, "CENTER", 0, 0)
            mod.SetWrappedText(label, max(30, slotW - 8), "CENTER")
            label:ClearAllPoints()
            label:SetPoint("TOP", button, "TOP", 0, -4)
            local height = max(8 + mod.SnapToPixelGrid(label:GetStringHeight()), barH + 8)
            contentFrame:SetHeight(height)
            button:SetHeight(height)
            if rest:IsShown() then
                rest:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -2, -2)
            end
            if mailArt:IsShown() then
                mailArt:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 2, -2)
            end
        else
            -- Mail, time, rest in a row, as wide as they need (up to the budget).
            local budget = K.HBudget(inst, 120)
            local restW = rest:IsShown() and restSize + 4 or 0
            local mailW = mailArt:IsShown() and mailSize + 8 or 0
            mod.SetFont(label, fontSize, barCtx.cfg)
            mod.ResetInlineText(label, "CENTER")
            local textW = mod.SnapToPixelGrid(label:GetStringWidth())
            local textH = max(mod.SnapToPixelGrid(label:GetStringHeight()), 1)
            local width = min(budget, max(textW, 1) + restW + mailW)
            contentFrame:SetSize(width, textH)
            button:SetSize(width, textH)
            button:ClearAllPoints()
            button:SetPoint("CENTER")
            label:ClearAllPoints()
            label:SetPoint("CENTER")
            -- The rest icon sits towards the screen's middle.
            if rest:IsShown() then
                if barCtx.IsBarAtTop() then
                    rest:SetPoint("TOPLEFT", label, "TOPRIGHT", 2, -12)
                else
                    rest:SetPoint("BOTTOMLEFT", label, "BOTTOMRIGHT", 2, 12)
                end
            end
            if mailArt:IsShown() then
                mailArt:SetPoint("RIGHT", label, "LEFT", -8, 0)
            end
        end
        K.MaybeRelayout(inst)
    end

    -- Every second: a draw only when the minute on screen changes.
    local function Tick()
        if Now() ~= drawnTime then
            inst:Refresh()
        end
    end

    -- Resting and mail: a draw only when what they show changes (the mailbox
    -- sends MAIL_INBOX_UPDATE over and over while it is open). The end of
    -- combat draws only if something changed during it.
    inst.eventFrame = K.MakeEventFrame(inst, function(self, event)
        if event == "PLAYER_REGEN_ENABLED" then
            if owesLayout then
                self:Refresh()
            end
        elseif owesLayout or InCombatLockdown() or State(Now()) ~= drawnState then
            self:Refresh()
        end
    end)

    local function ShowTooltip()
        mod.Tip_Begin(button)
        -- date()'s day and month names are English in every client, so the
        -- game's translated names are used, in the order its FULLDATE gives.
        local today = C_DateAndTime.GetCurrentCalendarTime()
        mod.Tip_AddLine(
            format(
                FULLDATE,
                CALENDAR_WEEKDAY_NAMES[today.weekday],
                CALENDAR_FULLDATE_MONTH_NAMES[today.month],
                today.monthDay,
                today.year
            ),
            1,
            1,
            1
        )
        local hour, minute = GetGameTime()
        local _, use24 = Modes()
        mod.Tip_AddDouble(
            L["SERVER_TIME"],
            ClockText(floor(hour), floor(minute), use24),
            0.6,
            0.6,
            0.6,
            1,
            1,
            1
        )

        local saved = GetNumSavedInstances and GetNumSavedInstances() or 0
        if saved > 0 then
            mod.Tip_AddLine(" ")
            mod.Tip_AddLine(L["SAVED_INSTANCES"], 1, 0.82, 0)
            for i = 1, saved do
                local name, _, reset, _, locked, extended = GetSavedInstanceInfo(i)
                if locked or extended then
                    mod.Tip_AddDouble(name, mod.FormatTimeLeft(reset), 1, 1, 1, 0.6, 0.6, 0.6)
                end
            end
        end
        mod.Tip_AddLine(" ")
        local daily = GetQuestResetTime and GetQuestResetTime() or 0
        if daily > 0 then
            mod.Tip_AddDouble(L["DAILY_RESET"], mod.FormatTimeLeft(daily), 0.6, 0.6, 0.6, 1, 1, 1)
        end
        local weekly = C_DateAndTime
                and C_DateAndTime.GetSecondsUntilWeeklyReset
                and C_DateAndTime.GetSecondsUntilWeeklyReset()
            or 0
        if weekly > 0 then
            mod.Tip_AddDouble(L["WEEKLY_RESET"], mod.FormatTimeLeft(weekly), 0.6, 0.6, 0.6, 1, 1, 1)
        end
        if HasNewMail() then
            mod.Tip_AddLine(" ")
            mod.Tip_AddLine(L["YOU_HAVE_MAIL"], 1, 0.82, 0)
        end
        mod.Tip_AddLine(" ")
        mod.Tip_AddDouble(L["LEFT_CLICK"], L["TOGGLE_CALENDAR"], 1, 1, 1, 1, 1, 1)
        mod.Tip_AddDouble(L["RIGHT_CLICK"], L["TOGGLE_CLOCK"], 1, 1, 1, 1, 1, 1)
        mod.Tip_AddDouble(L["SHIFT_MIDDLE_CLICK"], L["RELOAD_UI"], 1, 1, 1, 1, 1, 1)
        mod.Tip_Show()
    end

    button:SetScript("OnEnter", function()
        hovered = true
        Paint()
        ShowTooltip()
    end)
    button:SetScript("OnLeave", function()
        hovered = false
        Paint()
        mod.Tip_Hide(button)
    end)
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "MiddleButton" and IsShiftKeyDown() then
            -- Never mid-combat: a reload drops the player out of the fight.
            if not InCombatLockdown() then
                CludesUI.RequestReload(CludesUI.L("Reload UI"), CludesUI.L("Reload the UI now?"))
            end
        elseif mouseButton == "LeftButton" then
            if ToggleCalendar then
                ToggleCalendar()
            end
        elseif mouseButton == "RightButton" then
            if ToggleTimeManager then
                ToggleTimeManager()
            elseif GameTimeFrame then
                GameTimeFrame:Click()
            end
        end
    end)

    function inst:Enable()
        contentFrame:Show()
        owesLayout = false
        drawnTime, drawnState = nil, nil
        K.RegisterInstEvents(self)
        mod.RegisterHeartbeat(tickKey, Tick)
    end

    function inst:Disable()
        mod.UnregisterHeartbeat(tickKey)
        K.UnregisterInstEvents(self)
        rest:Hide()
        contentFrame:Hide()
    end

    function inst:GetAutoLength()
        if barCtx.IsVertical() then
            local textH = label:GetStringHeight() or FontSize()
            return max(8 + textH + 8, barCtx.GetThickness(), 60)
        end
        local width = button:GetWidth() or 80
        if Settings().showResting ~= false then
            width = width + RestSize() + 4
        end
        if ShowsMail() then
            width = width + RestSize() + 8 + 8
        end
        return max(width, 60)
    end

    -- Stops ticking and listening, even if it was never disabled first.
    function inst:Destroy()
        self._dead = true
        mod.UnregisterHeartbeat(tickKey)
        K.UnregisterInstEvents(self)
        contentFrame:Hide()
    end

    return inst
end
