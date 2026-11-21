if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not CludesUI.IS_FOREVER then return end
-------------------------------------------------------------------------------
--  CludesUIQuestTracker_QuestAudio.lua - the quest voice-over addon's Play
--  button on our tracker (WoW Forever; the owner's pick, 7 Nov 2026).
--
--  That addon puts its Play button on Blizzard's tracker blocks, which our
--  tracker keeps muted, so the same button goes on our quest title rows
--  through the row hooks (CludesUI.RegisterQuestTrackerRow). The addon's
--  own functions make and bind it: its public button dressing, and its quest
--  log's play binding, reached through the one global it keeps stable.
--
--  Set up at login only while our tracker is in use and the addon offers
--  every function used here. If one of its calls fails later the bridge
--  turns off for the session and hides its buttons, instead of erroring on
--  every row.
-------------------------------------------------------------------------------
local _, mod = ...

local SIZE, ROOM = 14, 16 -- the button, and the room it takes right of a title
local BOX = "QuestLog-icon-ticksquare" -- the quest log's tracking box, which the button matches
local ORIGIN = "CludesUI's quest tracker" -- how the addon's debug log names the button

-- The addon's quest overlay and its public side, if it offers all we use.
local function VoiceOverAddon()
    local environ, spoken = _G.VoiceOver, _G.Spoken
    local ui = type(environ) == "table" and rawget(environ, "QuestOverlayUI")
    if type(ui) ~= "table" or type(spoken) ~= "table" then return nil end
    for _, fn in ipairs({ "ShowsTrackerButton", "BindPlayButton", "SetPlayButtonState", "FollowQueue" }) do
        if type(ui[fn]) ~= "function" then return nil end
    end
    if type(spoken.DressBoxButton) ~= "function" or type(spoken.RegisterCallback) ~= "function" then
        return nil
    end
    return ui, spoken
end

local function Install()
    if not mod.UseCustomTracker() then return end
    local ui, spoken = VoiceOverAddon()
    if not ui then return end

    local buttons = {} -- row -> its button
    local voiced = {} -- questID -> whether the addon offers Play for it
    local broken = false

    local function Voiced(questID)
        local known = voiced[questID]
        if known == nil then
            known = ui:ShowsTrackerButton(questID) and true or false
            voiced[questID] = known
        end
        return known
    end

    local function NewButton(row)
        local button = CreateFrame("Button", nil, row)
        button:SetSize(SIZE, SIZE)
        button:SetHitRectInsets(1, 1, 1, 1)
        button:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
        spoken:DressBoxButton(button)
        button:SetBox(BOX, SIZE, SIZE)
        -- Its glyph follows the addon's queue (play, stop, replay).
        button.setPlayState = ui.FollowQueue
        -- Dark behind the box: the tracker can sit straight on the world.
        local back = button:CreateTexture(nil, "BACKGROUND", nil, -1)
        back:SetPoint("TOPLEFT", 1, -1)
        back:SetPoint("BOTTOMRIGHT", -1, 1)
        back:SetColorTexture(0, 0, 0, 0.6)
        return button
    end

    local function Dress(row, questID)
        local button = buttons[row]
        if not Voiced(questID) then
            if button then button:Hide() end
            return
        end
        if not button then
            button = NewButton(row)
            buttons[row] = button
        end
        -- Bound again only when the pooled row now shows another quest (a
        -- binding sets new scripts).
        if button.questID ~= questID then
            button.soundData = nil
            ui:BindPlayButton(button, questID, C_QuestLog.GetTitleForQuestID(questID) or "", ORIGIN)
            ui:SetPlayButtonState(button)
        end
        button:Show()
    end

    local function Row(row, questID)
        if broken then return end
        if not pcall(Dress, row, questID) then
            broken = true
            for _, button in pairs(buttons) do
                button:Hide()
            end
        end
    end
    -- Registered under the addon's own name: should it add a row hook of its
    -- own, the first one stands and the other is refused, so no row gets two.
    if not CludesUI.RegisterQuestTrackerRow("Spoken", Row, ROOM) then return end

    -- What Voiced reads can change: the voice packs load after login, the
    -- addon's quest part can be switched, and its tracker button setting
    -- (like every settings change) runs its tracker sweep.
    local function AskAgain()
        wipe(voiced)
        CludesUI.RefreshQuestTrackerRows()
    end
    spoken:RegisterCallback("VOICE_PACKS_LOADED", AskAgain)
    spoken:RegisterCallback("PART_SWITCHED", function(part)
        if part == "quests" then AskAgain() end
    end)
    if type(ui.UpdateTrackerButtons) == "function" then
        hooksecurefunc(ui, "UpdateTrackerButtons", AskAgain)
    end
end

-- The addon loads after this one; all it offers is there by login.
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Install()
end)
