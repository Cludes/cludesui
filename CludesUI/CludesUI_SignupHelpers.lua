if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if CUI.IS_FOREVER then return end -- no premade group list on WoW Forever: no hooks, no API (the option rows are not built there)
-------------------------------------------------------------------------------
--  CludesUI_SignupHelpers.lua
--  Premade group sign-up helpers. Quality of Life's and Group Finder's option
--  rows drive the same account-wide settings on CludesUIDB:
--
--  Quick Signup (quickSignup): double-clicking a group listing signs up, the
--  Sign Up dialog confirms itself, and the Dungeon Finder role check accepts
--  itself with the saved roles. Holding Shift keeps either dialog open.
--
--  Persistent Signup Note (persistSignupNote, the note in signupNote): the
--  Sign Up dialog keeps the note typed into it between sign-ups, and a Copy
--  button beside the note field offers the saved note for Ctrl+C.
--
--  API: CludesUI._applyQuickSignup() / _applyPersistSignupNote() after a
--  setting changes, CludesUI.GetPersistentSignupNote() /
--  SetPersistentSignupNote(note). The saved state is applied at PLAYER_LOGIN
--  while Quality of Life or Group Finder is loaded (the API does nothing
--  before it, or at all with neither loaded). Nothing is hooked until a
--  setting is first turned on; hooks cannot be removed, so their bodies
--  return at once while it is off, and the role-check event is registered
--  only while Quick Signup is on.
-------------------------------------------------------------------------------

local ready = false -- set at PLAYER_LOGIN

-------------------------------------------------------------------------------
--  Quick Signup
-------------------------------------------------------------------------------
local lastClickTime = 0
local lastClickEntry = nil
local DOUBLE_CLICK_THRESHOLD = 0.4
local installed = false -- hooks are installed ONCE, on first enable
local roleFrame -- Dungeon Finder role-check listener (created on install)

local function InstallQuickSignupHooks()
    if installed then return end
    installed = true

    hooksecurefunc("LFGListSearchEntry_OnClick", function(record, btnFrame)
        if not (CludesUIDB and CludesUIDB.quickSignup) then return end
        if btnFrame == "RightButton" then return end

        local panelFrame = LFGListFrame and LFGListFrame.SearchPanel
        if not panelFrame then return end
        -- Blizzard's select check tests the result's fields, which are secret
        -- during chat messaging lockdown: stand down instead of erroring.
        local resultID = record.resultID
        if issecretvalue(resultID) then return end
        local details = C_LFGList.GetSearchResultInfo(resultID)
        if
            type(details) ~= "table"
            or issecretvalue(details)
            or not canaccesstable(details)
            or issecretvalue(details.isDelisted)
        then
            return
        end
        if not LFGListSearchPanelUtil_CanSelectResult(resultID) then return end
        if not panelFrame.SignUpButton or not panelFrame.SignUpButton:IsEnabled() then return end

        local nowTime = GetTime()
        if lastClickEntry == resultID and (nowTime - lastClickTime) < DOUBLE_CLICK_THRESHOLD then
            if panelFrame.selectedResult ~= resultID then
                LFGListSearchPanel_SelectResult(panelFrame, resultID)
            end
            LFGListSearchPanel_SignUp(panelFrame)
            lastClickEntry = nil
            lastClickTime = 0
        else
            lastClickEntry = resultID
            lastClickTime = nowTime
        end
    end)

    -- Confirm the Sign Up dialog; holding Shift keeps it open (e.g. to type a
    -- signup note).
    if LFGListApplicationDialog then
        LFGListApplicationDialog:HookScript("OnShow", function(self)
            if not (CludesUIDB and CludesUIDB.quickSignup) then return end
            if self.SignUpButton:IsEnabled() and not IsShiftKeyDown() then self.SignUpButton:Click() end
        end)
    end

    -- Dungeon Finder role check
    roleFrame = CreateFrame("Frame")
    roleFrame:SetScript("OnEvent", function()
        if not (CludesUIDB and CludesUIDB.quickSignup) then return end
        if not UnitInParty("player") then return end
        -- Holding Shift skips the auto role-check accept
        if IsShiftKeyDown() then return end
        local leader, tank, healer, dps = GetLFGRoles()
        if LFDRoleCheckPopupRoleButtonTank.checkButton:IsEnabled() then
            LFDRoleCheckPopupRoleButtonTank.checkButton:SetChecked(tank)
        end
        if LFDRoleCheckPopupRoleButtonHealer.checkButton:IsEnabled() then
            LFDRoleCheckPopupRoleButtonHealer.checkButton:SetChecked(healer)
        end
        if LFDRoleCheckPopupRoleButtonDPS.checkButton:IsEnabled() then
            LFDRoleCheckPopupRoleButtonDPS.checkButton:SetChecked(dps)
        end
        LFDRoleCheckPopupAcceptButton:Enable()
        LFDRoleCheckPopupAcceptButton:Click()
    end)
end

-- Installs the hooks on first enable and matches the role-check event to the
-- setting.
CUI._applyQuickSignup = function()
    if not ready then return end
    local enabled = CludesUIDB and CludesUIDB.quickSignup
    if enabled then InstallQuickSignupHooks() end
    if roleFrame then
        if enabled then
            roleFrame:RegisterEvent("LFG_ROLE_CHECK_SHOW")
        else
            roleFrame:UnregisterEvent("LFG_ROLE_CHECK_SHOW")
        end
    end
end

-------------------------------------------------------------------------------
--  Persistent Signup Note
-------------------------------------------------------------------------------
local vanilla -- Blizzard's LFGListApplicationDialog_Show, taken at PLAYER_LOGIN
local patched = false
local copyHooked = false
local copyHelper
local hidingCopyField = false

local function LimitNote(textValue)
    if type(textValue) ~= "string" then return "" end
    textValue = textValue:gsub("[\r\n]+", " ")
    local bytes, position, total, last = #textValue, 1, 0, 0
    while position <= bytes and total < 63 do
        local byte = textValue:byte(position)
        local width = byte < 128 and 1 or byte < 224 and 2 or byte < 240 and 3 or 4
        if position + width - 1 > bytes then break end
        last = position + width - 1
        position = last + 1
        total = total + 1
    end
    return textValue:sub(1, last)
end

local function SavedNote() return LimitNote(CludesUIDB and CludesUIDB.signupNote) end

local function NoteEnabled() return CludesUIDB and CludesUIDB.persistSignupNote end

local function CloseCopyField(focusTarget)
    if not copyHelper then return end
    copyHelper.buttonText:SetText(CUI.L("Copy"))
    if copyHelper.copyBox:IsShown() then
        hidingCopyField = true
        copyHelper.copyBox:Hide()
        copyHelper.copyBox:ClearFocus()
        hidingCopyField = false
    end
    if focusTarget and copyHelper.targetEditBox then copyHelper.targetEditBox:SetFocus() end
end

local function RefreshCopyHelper(dialog)
    if not NoteEnabled() or not dialog or not dialog:IsShown() then return end
    local description = dialog and dialog.Description
    local editBox = description and description.EditBox
    if not editBox then return end
    if SavedNote() == "" then
        if copyHelper then copyHelper:Hide() end
        return
    end

    if not copyHelper then
        local ACC = CUI.CLUDES_GREEN
        local FONT = CUI.GetFontPath("main") or CUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF"
        local Pix = CUI.PP

        local helper = CreateFrame("Frame", nil, dialog)
        helper:SetAllPoints(dialog)
        helper:EnableMouse(false)

        local btnFrame = CreateFrame("Button", nil, helper)
        btnFrame:SetSize(42, 20)
        btnFrame:SetPoint("LEFT", description, "RIGHT", 4, 0)
        btnFrame:EnableMouse(true)

        local buttonBg = btnFrame:CreateTexture(nil, "BACKGROUND")
        buttonBg:SetAllPoints()
        buttonBg:SetColorTexture(0.020, 0.025, 0.031, 0.92)
        local buttonBorder = CUI.MakeBorder(btnFrame, ACC.r, ACC.g, ACC.b, 0.72, Pix)

        local buttonText = btnFrame:CreateFontString(nil, "OVERLAY")
        buttonText:SetFont(FONT, 9, "")
        buttonText:SetPoint("CENTER", 0, 0)
        buttonText:SetText(CUI.L("Copy"))
        buttonText:SetTextColor(ACC.r, ACC.g, ACC.b, 0.92)

        local copyBox = CreateFrame("EditBox", nil, helper)
        copyBox:SetPoint("TOPLEFT", description, "TOPLEFT", 0, 0)
        copyBox:SetPoint("BOTTOMRIGHT", description, "BOTTOMRIGHT", 0, 0)
        copyBox:SetAutoFocus(false)
        copyBox:SetFont(FONT, 11, "")
        copyBox:SetTextColor(1, 1, 1, 0.96)
        copyBox:SetTextInsets(5, 5, 0, 0)
        copyBox:SetJustifyH("LEFT")
        copyBox:SetHighlightColor(ACC.r, ACC.g, ACC.b, 0.45)
        copyBox:EnableMouse(true)
        local copyBg = copyBox:CreateTexture(nil, "BACKGROUND")
        copyBg:SetAllPoints()
        copyBg:SetColorTexture(0.020, 0.025, 0.031, 1)
        CUI.MakeBorder(copyBox, ACC.r, ACC.g, ACC.b, 0.9, Pix)
        copyBox:Hide()

        copyBox:SetScript("OnEditFocusLost", function()
            if not hidingCopyField and not btnFrame:IsMouseOver() then CloseCopyField(false) end
        end)
        copyBox:SetScript("OnKeyUp", function(_, key)
            if key == "C" and IsControlKeyDown() then CloseCopyField(true) end
        end)

        btnFrame:SetScript("OnEnter", function()
            buttonBorder:SetColor(ACC.r, ACC.g, ACC.b, 1)
            buttonText:SetTextColor(ACC.r, ACC.g, ACC.b, 1)
        end)
        btnFrame:SetScript("OnLeave", function()
            buttonBorder:SetColor(ACC.r, ACC.g, ACC.b, 0.72)
            buttonText:SetTextColor(ACC.r, ACC.g, ACC.b, 0.92)
        end)
        btnFrame:SetScript("OnClick", function()
            if copyBox:IsShown() then
                CloseCopyField(false)
                return
            end
            local note = SavedNote()
            if note == "" then return end
            copyBox:SetText(note)
            copyBox:Show()
            copyBox:SetFocus()
            copyBox:HighlightText()
            buttonText:SetText("Ctrl+C")
        end)

        helper.button = btnFrame
        helper.buttonText = buttonText
        helper.copyBox = copyBox
        copyHelper = helper
    end

    copyHelper.targetEditBox = editBox
    copyHelper:SetFrameLevel(dialog:GetFrameLevel() + 20)
    copyHelper.button:SetFrameLevel(copyHelper:GetFrameLevel() + 1)
    copyHelper.copyBox:SetFrameLevel(copyHelper:GetFrameLevel() + 2)
    CloseCopyField()
    copyHelper:Show()
end

-- Blizzard's show without its clear of the application text fields, so the
-- typed note stays.
local function PatchedShow(self, resultID)
    if resultID then
        self.resultID = resultID
        -- Apply-phase search result is SECRET: activityID can be secret and
        -- activityIDs a secret table whose indexing throws. Guard every read; degrade to nil rather than erroring the dialog.
        pcall(function()
            -- Cleared up-front so a mid-read throw can't leave a stale activityID from a previous dialog open.
            self.activityID = nil
            local details = C_LFGList.GetSearchResultInfo(resultID)
            if type(details) ~= "table" then return end
            local aid = details.activityID
            if issecretvalue(aid) then aid = nil end
            if aid == nil and details.activityIDs and not issecretvalue(details.activityIDs) then
                aid = details.activityIDs[1]
                if issecretvalue(aid) then aid = nil end
            end
            self.activityID = aid
        end)
    end
    LFGListApplicationDialog_UpdateRoles(self)
    StaticPopupSpecial_Show(self)
end

CUI.GetPersistentSignupNote = function() return SavedNote() end

local function SyncPatch()
    if not ready then return end
    if NoteEnabled() then
        if not patched then
            LFGListApplicationDialog_Show = PatchedShow
            patched = true
        end
        -- Another addon can replace the show function after login; the dialog hook survives it.
        if LFGListApplicationDialog and not copyHooked then
            LFGListApplicationDialog:HookScript("OnShow", RefreshCopyHelper)
            copyHooked = true
        end
        RefreshCopyHelper(LFGListApplicationDialog)
    else
        if patched then
            if LFGListApplicationDialog_Show == PatchedShow then LFGListApplicationDialog_Show = vanilla end
            patched = false
        end
        if copyHelper then copyHelper:Hide() end
    end
end

CUI.SetPersistentSignupNote = function(note)
    if not CludesUIDB then CludesUIDB = {} end
    CludesUIDB.signupNote = LimitNote(note)
    SyncPatch()
end

CUI._applyPersistSignupNote = SyncPatch

-------------------------------------------------------------------------------
--  Login: apply the saved settings
-------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    -- Only while a module with the option rows is loaded; with neither, the
    -- API stays inert and nothing is hooked.
    local hosts = CUI._ModuleNS
    if not (hosts.CludesUIQoL or hosts.CludesUIGroupFinder) then return end
    vanilla = LFGListApplicationDialog_Show
    ready = true
    CUI._applyQuickSignup()
    SyncPatch()
end)
