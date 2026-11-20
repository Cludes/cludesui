if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_BlizzardSkin_Dialogs.lua
--
--  Quick Keybind frame, premade group invite, LFG application dialog and
--  the game menu.
--  Reads CludesUIBlizzardSkin.lua through ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIBlizzardSkin.lua or an earlier CUI_BlizzardSkin_*.lua file
-- failed to load.
if not Inner or Inner.last ~= "TooltipSkin" then
    return
end

local GetFFD = Inner.GetFFD

-------------------------------------------------------------------------------
--  Quick Keybind Frame: dark reskin matching the queue popup style.
-------------------------------------------------------------------------------
do
    local _qkbSkinned = false
    local function SkinQuickKeybindFrame()
        if _qkbSkinned then
            return
        end
        local qkb = QuickKeybindFrame
        if not qkb then
            return
        end
        _qkbSkinned = true

        local RS = CludesUI.RESKIN
        local _PP = CludesUI and CludesUI.PP

        if qkb.NineSlice then
            qkb.NineSlice:SetAlpha(0)
        end
        if qkb.BG then
            qkb.BG:SetAlpha(0)
        end
        if qkb.Border then
            qkb.Border:SetAlpha(0)
        end
        if qkb.Bg then
            qkb.Bg:SetAlpha(0)
        end
        local regionList = { qkb:GetRegions() }
        for idx = 1, #regionList do
            local region = regionList[idx]
            if region and region:IsObjectType("Texture") and not GetFFD(region).owned then
                region:SetAlpha(0)
            end
        end

        local bgFrame = CreateFrame("Frame", nil, qkb)
        bgFrame:SetAllPoints(qkb)
        bgFrame:SetFrameLevel(math.max(1, qkb:GetFrameLevel() - 1))
        local backdrop = bgFrame:CreateTexture(nil, "ARTWORK")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(RS.BG_R, RS.BG_G, RS.BG_B, RS.QT_ALPHA)
        GetFFD(backdrop).owned = true
        if _PP and _PP.CreateBorder then
            _PP.CreateBorder(bgFrame, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
        end

        -- The header is a Frame with sub-textures: strip art, raise level.
        if qkb.Header then
            qkb.Header:SetFrameLevel(qkb:GetFrameLevel() + 2)
            if qkb.Header.LeftBG then
                qkb.Header.LeftBG:SetAlpha(0)
            end
            if qkb.Header.CenterBG then
                qkb.Header.CenterBG:SetAlpha(0)
            end
            if qkb.Header.RightBG then
                qkb.Header.RightBG:SetAlpha(0)
            end
        end
        -- Raise the instruction/output text above our bg.
        if qkb.InstructionText then
            qkb.InstructionText:SetDrawLayer("OVERLAY", 6)
        end
        if qkb.OutputText then
            qkb.OutputText:SetDrawLayer("OVERLAY", 6)
        end
        if qkb.CancelDescriptionText then
            qkb.CancelDescriptionText:SetDrawLayer("OVERLAY", 6)
        end

        local btnNames = { "OkayButton", "CancelButton", "DefaultsButton" }
        -- Native mode leaves button text un-recolored.
        local er, eg, editField = CludesUI._getPopupMenuButtonTextColor()
        local ACC = { r = er, g = eg, b = editField }
        local useAccent = (CludesUI._getPopupMenuElementMode() ~= "native") and ACC
        for _, name in ipairs(btnNames) do
            local button = qkb[name]
            if button and not GetFFD(button).skinned then
                GetFFD(button).skinned = true
                local regions2 = { button:GetRegions() }
                for jdx = 1, #regions2 do
                    local region = regions2[jdx]
                    if
                        region
                        and region:IsObjectType("Texture")
                        and not GetFFD(region).owned
                        and region ~= button:GetFontString()
                    then
                        region:SetAlpha(0)
                    end
                end
                if button.Left then
                    button.Left:SetAlpha(0)
                end
                if button.Middle then
                    button.Middle:SetAlpha(0)
                end
                if button.Right then
                    button.Right:SetAlpha(0)
                end
                -- C++ swaps these on press, so re-suppress via a SetAlpha hook.
                for _, texKey in ipairs({ "Left", "Middle", "Right" }) do
                    local texture = button[texKey]
                    if texture and texture.SetAlpha then
                        hooksecurefunc(texture, "SetAlpha", function(self, a)
                            if a > 0 then
                                self:SetAlpha(0)
                            end
                        end)
                    end
                end
                local btnBg = button:CreateTexture(nil, "BACKGROUND", nil, -6)
                btnBg:SetAllPoints()
                btnBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
                GetFFD(btnBg).owned = true
                if _PP and _PP.CreateBorder then
                    if useAccent then
                        _PP.CreateBorder(button, ACC.r, ACC.g, ACC.b, 0.5, 1, "OVERLAY", 7)
                    else
                        _PP.CreateBorder(button, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
                    end
                end
                -- Accent the text; Blizzard's hover turns it white.
                local fontStr = button:GetFontString()
                if fontStr and useAccent then
                    fontStr:SetTextColor(ACC.r, ACC.g, ACC.b, 1)
                end
            end
        end

        -- UseCharacterBindingsButton is a CheckButton: left functional, only its label is raised for legibility.
        if qkb.UseCharacterBindingsButton and qkb.UseCharacterBindingsButton.SetCheckedTexture then
            local cbText = qkb.UseCharacterBindingsButton.Text or qkb.UseCharacterBindingsButton.text
            if cbText then
                cbText:SetDrawLayer("OVERLAY", 6)
            end
        end
    end

    -- Blizzard_QuickKeybind is LoadOnDemand, so the frame may not exist at login: try after login, with ADDON_LOADED as the late-load fallback.
    local _qkbHooked = false
    local function TryHookQKB()
        if _qkbHooked then
            return
        end
        if not CludesUIDB then
            return
        end
        if CludesUIDB.reskinQueuePopup == false then
            return
        end
        local qkb = QuickKeybindFrame
        if qkb then
            _qkbHooked = true
            qkb:HookScript("OnShow", SkinQuickKeybindFrame)
        end
    end
    local qkbSkinFrame = CreateFrame("Frame")
    qkbSkinFrame:RegisterEvent("PLAYER_LOGIN")
    qkbSkinFrame:RegisterEvent("ADDON_LOADED")
    qkbSkinFrame:SetScript("OnEvent", function(self, evt, arg1)
        if evt == "PLAYER_LOGIN" then
            self:UnregisterEvent("PLAYER_LOGIN")
            C_Timer.After(2, TryHookQKB)
        elseif evt == "ADDON_LOADED" and arg1 == "Blizzard_QuickKeybind" then
            self:UnregisterEvent("ADDON_LOADED")
            C_Timer.After(0, TryHookQKB)
        end
    end)
end

-------------------------------------------------------------------------------
--  Premade Group Invite Popup: same dark skin as the LFG queue popup.
--  LFGListInviteDialog appears when a group leader accepts your application.
-------------------------------------------------------------------------------
do
    local function SkinPremadeInvite()
        local dialog = _G.LFGListInviteDialog
        if not dialog then
            return
        end
        if not CludesUIDB or not CludesUIDB.reskinQueuePopup then
            return
        end
        if GetFFD(dialog).skinned then
            return
        end
        GetFFD(dialog).skinned = true

        local RS = CludesUI.RESKIN
        local _PP = CludesUI and CludesUI.PP

        -- Border/decoration only; role icon and content are preserved.
        if dialog.Bg then
            dialog.Bg:SetAlpha(0)
        end
        if dialog.BG then
            dialog.BG:SetAlpha(0)
        end
        if dialog.NineSlice then
            dialog.NineSlice:SetAlpha(0)
        end
        if dialog.Border then
            dialog.Border:SetAlpha(0)
        end

        local backdrop = dialog:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(RS.BG_R, RS.BG_G, RS.BG_B, RS.QT_ALPHA)
        GetFFD(backdrop).owned = true
        if _PP and _PP.CreateBorder then
            _PP.CreateBorder(dialog, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
        end

        local function _accentOn()
            -- Native mode leaves text/border un-accented.
            return CludesUI._getPopupMenuElementMode() ~= "native"
        end
        for _, btnName in ipairs({ "AcceptButton", "DeclineButton", "AcknowledgeButton" }) do
            local button = dialog[btnName]
            if button then
                -- Re-stripped every show; Blizzard re-applies the art.
                local regionList = { button:GetRegions() }
                for jdx = 1, #regionList do
                    local region = regionList[jdx]
                    if
                        region
                        and region:IsObjectType("Texture")
                        and not GetFFD(region).owned
                        and region ~= button:GetFontString()
                    then
                        region:SetAlpha(0)
                    end
                end
                if button.Left then
                    button.Left:SetAlpha(0)
                end
                if button.Middle then
                    button.Middle:SetAlpha(0)
                end
                if button.Right then
                    button.Right:SetAlpha(0)
                end
                if not GetFFD(button).skinned then
                    GetFFD(button).skinned = true
                    for _, texKey in ipairs({ "Left", "Middle", "Right" }) do
                        local texture = button[texKey]
                        if texture and texture.SetAlpha then
                            hooksecurefunc(texture, "SetAlpha", function(self, a)
                                if a > 0 then
                                    self:SetAlpha(0)
                                end
                            end)
                        end
                    end
                    local er, eg, editField = CludesUI._getPopupMenuButtonTextColor()
                    local ACC = { r = er, g = eg, b = editField }
                    local useAccent = _accentOn() and ACC
                    local btnBg = button:CreateTexture(nil, "BACKGROUND", nil, -6)
                    btnBg:SetAllPoints()
                    btnBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
                    GetFFD(btnBg).owned = true
                    if _PP and _PP.CreateBorder then
                        if useAccent then
                            _PP.CreateBorder(button, ACC.r, ACC.g, ACC.b, 0.5, 1, "OVERLAY", 7)
                        else
                            _PP.CreateBorder(button, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
                        end
                    end
                end
                -- Text accent re-applied every show.
                local er, eg, editField = CludesUI._getPopupMenuButtonTextColor()
                local ACC = { r = er, g = eg, b = editField }
                local useAccent = _accentOn() and ACC
                local fontStr = button:GetFontString()
                if fontStr and useAccent then
                    fontStr:SetTextColor(ACC.r, ACC.g, ACC.b, 1)
                end
            end
        end
    end

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("ADDON_LOADED")
    frame:SetScript("OnEvent", function(self, _, addon)
        if _G.LFGListInviteDialog then
            self:UnregisterAllEvents()
            _G.LFGListInviteDialog:HookScript("OnShow", SkinPremadeInvite)
        end
    end)
end

-------------------------------------------------------------------------------
--  LFG Application Dialog (Sign Up popup): same dark skin.
-------------------------------------------------------------------------------
do
    local function SkinApplicationDialog()
        local dialog = _G.LFGListApplicationDialog
        if not dialog then
            return
        end
        if CludesUIDB and CludesUIDB.reskinQueuePopup == false then
            return
        end
        if GetFFD(dialog).skinned then
            return
        end
        GetFFD(dialog).skinned = true

        local RS = CludesUI.RESKIN
        local _PP = CludesUI and CludesUI.PP

        -- Border/decoration only; content is preserved.
        if dialog.Bg then
            dialog.Bg:SetAlpha(0)
        end
        if dialog.BG then
            dialog.BG:SetAlpha(0)
        end
        if dialog.NineSlice then
            dialog.NineSlice:SetAlpha(0)
        end
        if dialog.Border then
            dialog.Border:SetAlpha(0)
        end

        local backdrop = dialog:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(RS.BG_R, RS.BG_G, RS.BG_B, RS.QT_ALPHA)
        GetFFD(backdrop).owned = true
        if _PP and _PP.CreateBorder then
            _PP.CreateBorder(dialog, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
        end

        local desc = _G.LFGListApplicationDialogDescription
        if desc then
            local regionList = { desc:GetRegions() }
            for idx = 1, #regionList do
                local region = regionList[idx]
                if region and region:IsObjectType("Texture") and not GetFFD(region).owned then
                    region:SetAlpha(0)
                end
            end
            if desc.NineSlice then
                desc.NineSlice:SetAlpha(0)
            end
            local descBg = desc:CreateTexture(nil, "BACKGROUND")
            descBg:SetAllPoints()
            descBg:SetColorTexture(0.06, 0.06, 0.06, 0.8)
            GetFFD(descBg).owned = true
            if _PP and _PP.CreateBorder then
                _PP.CreateBorder(desc, 1, 1, 1, 0.08, 1, "OVERLAY", 7)
            end
        end

        local function _accentOn()
            -- Native mode leaves text/border un-accented.
            return CludesUI._getPopupMenuElementMode() ~= "native"
        end
        for _, btnName in ipairs({ "SignUpButton", "CancelButton" }) do
            local button = dialog[btnName]
            if button and not GetFFD(button).skinned then
                GetFFD(button).skinned = true
                local regionList = { button:GetRegions() }
                for jdx = 1, #regionList do
                    local region = regionList[jdx]
                    if
                        region
                        and region:IsObjectType("Texture")
                        and not GetFFD(region).owned
                        and region ~= button:GetFontString()
                    then
                        region:SetAlpha(0)
                    end
                end
                if button.Left then
                    button.Left:SetAlpha(0)
                end
                if button.Middle then
                    button.Middle:SetAlpha(0)
                end
                if button.Right then
                    button.Right:SetAlpha(0)
                end
                for _, texKey in ipairs({ "Left", "Middle", "Right" }) do
                    local texture = button[texKey]
                    if texture and texture.SetAlpha then
                        hooksecurefunc(texture, "SetAlpha", function(self, a)
                            if a > 0 then
                                self:SetAlpha(0)
                            end
                        end)
                    end
                end
                local er, eg, editField = CludesUI._getPopupMenuButtonTextColor()
                local ACC = { r = er, g = eg, b = editField }
                local useAccent = _accentOn() and ACC
                local btnBg = button:CreateTexture(nil, "BACKGROUND", nil, -6)
                btnBg:SetAllPoints()
                btnBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
                GetFFD(btnBg).owned = true
                if _PP and _PP.CreateBorder then
                    if useAccent then
                        _PP.CreateBorder(button, ACC.r, ACC.g, ACC.b, 0.5, 1, "OVERLAY", 7)
                    else
                        _PP.CreateBorder(button, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
                    end
                end
                local fontStr = button:GetFontString()
                if fontStr and useAccent then
                    fontStr:SetTextColor(ACC.r, ACC.g, ACC.b, 1)
                end
            end
        end
    end

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("ADDON_LOADED")
    frame:SetScript("OnEvent", function(self, _, addon)
        if _G.LFGListApplicationDialog then
            self:UnregisterAllEvents()
            _G.LFGListApplicationDialog:HookScript("OnShow", SkinApplicationDialog)
        end
    end)
end

-------------------------------------------------------------------------------
--  Game Menu Skinning
--  Restyles the pause menu (GameMenuFrame) with CUI dark style + border.
--  Runs once on PLAYER_LOGIN so GameMenuFrame is available.
-------------------------------------------------------------------------------
do
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        if not GameMenuFrame then
            return
        end
        -- Independent toggle, default on: this is a popup menu, not a window, so no master reskin setting (window-skins style included) governs it.
        if CludesUIDB and CludesUIDB.reskinGameMenu == false then
            return
        end

        local RS = CludesUI.RESKIN

        local regionList = { GameMenuFrame:GetRegions() }
        for idx = 1, #regionList do
            local region = regionList[idx]
            if region and region:IsObjectType("Texture") then
                region:SetAlpha(0)
            end
        end
        if GameMenuFrame.NineSlice then
            GameMenuFrame.NineSlice:SetAlpha(0)
        end
        if GameMenuFrame.Border then
            GameMenuFrame.Border:SetAlpha(0)
        end
        -- Header: strip art, accent the title, nudge down.
        local header = GameMenuFrame.Header
        if header then
            local regions2 = { header:GetRegions() }
            for idx = 1, #regions2 do
                local region = regions2[idx]
                if region and region:IsObjectType("Texture") then
                    region:SetAlpha(0)
                end
            end
            local headerText = header.Text or (header.GetRegions and select(1, header:GetRegions()))
            if headerText and headerText.SetTextColor then
                local region, g, button = CludesUI._getPopupMenuButtonTextColor()
                headerText:SetTextColor(region, g, button, 1)
                local cuiFont = CludesUI.GetFontPath("blizzardSkin") or "Fonts\\FRIZQT__.TTF"
                local _, hSize = headerText:GetFont()
                headerText:SetFont(cuiFont, hSize or 16, "")
            end
            header:ClearAllPoints()
            header:SetPoint("TOP", GameMenuFrame, "TOP", 0, -10)
        end
        local gmBg = GameMenuFrame:CreateTexture(nil, "BACKGROUND")
        gmBg:SetAllPoints()
        gmBg:SetColorTexture(RS.BG_R, RS.BG_G, RS.BG_B, RS.QT_ALPHA)
        local function ApplyButtonStyle(button)
            local skinData = GetFFD(button)
            -- Blizzard's pooled buttons keep skin data in this addon's FFD; CUI's two custom
            -- Game Menu buttons are created by the parent addon and keep theirs in ITS FFD. Fall back to that store so live option changes also reach the CludesUI button.
            if not skinData.gameMenuInset and CludesUI._GetFFD then
                skinData = CludesUI._GetFFD(button)
            end
            if not skinData.gameMenuInset then
                return
            end
            local color = CludesUIDB and CludesUIDB.popupMenuButtonBackgroundColor
                or { r = 0.1, g = 0.1, b = 0.1, a = 0.8 }
            skinData.gameMenuButtonBg:SetColorTexture(color.r, color.g, color.b, color.a == nil and 0.8 or color.a)
            CludesUI._applyBlizzardConfiguredBorder(skinData.gameMenuInset, "popupMenuButton", 1)
            local fontStr = button:GetFontString()
            -- Native mode keeps Blizzard's own gold on our dark inset.
            if fontStr and CludesUI._getPopupMenuElementMode() ~= "native" then
                local region, g, button = CludesUI._getPopupMenuButtonTextColor()
                fontStr:SetTextColor(region, g, button, 1)
            end
        end
        local function ApplyMenuStyle()
            CludesUI._applyBlizzardConfiguredBorder(GameMenuFrame, "popupMenu", 1)
            if GameMenuFrame.buttonPool then
                for button in GameMenuFrame.buttonPool:EnumerateActive() do
                    ApplyButtonStyle(button)
                end
            end
            -- The CUI/Unlock custom buttons are created by the PARENT addon and stored in ITS namespace FFD (CludesUI._GetFFD), not this addon's own FFD; wrong table = dead code.
            local pd = CludesUI._GetFFD(GameMenuFrame)
            if pd and pd.cuiBtn then
                ApplyButtonStyle(pd.cuiBtn)
            end
            if pd and pd.unlockBtn then
                ApplyButtonStyle(pd.unlockBtn)
            end
        end
        ApplyMenuStyle()
        GameMenuFrame:HookScript("OnShow", ApplyMenuStyle)
        hooksecurefunc(GameMenuFrame, "InitButtons", function(dropMenu)
            if not dropMenu.buttonPool then
                return
            end
            for menuBtn in dropMenu.buttonPool:EnumerateActive() do
                if not GetFFD(menuBtn).skinned then
                    GetFFD(menuBtn).skinned = true
                    local regions2 = { menuBtn:GetRegions() }
                    for jdx = 1, #regions2 do
                        local region = regions2[jdx]
                        if region and region:IsObjectType("Texture") and region ~= menuBtn:GetFontString() then
                            region:SetAlpha(0)
                        end
                    end
                    if menuBtn.Left then
                        menuBtn.Left:SetAlpha(0)
                    end
                    if menuBtn.Middle then
                        menuBtn.Middle:SetAlpha(0)
                    end
                    if menuBtn.Right then
                        menuBtn.Right:SetAlpha(0)
                    end
                    for _, texKey in ipairs({ "Left", "Middle", "Right" }) do
                        local texture = menuBtn[texKey]
                        if texture and texture.SetAlpha then
                            hooksecurefunc(texture, "SetAlpha", function(self, a)
                                if a > 0 then
                                    self:SetAlpha(0)
                                end
                            end)
                        end
                    end
                    -- Inset container: bg + border sit 2px inside the button edges for a tighter look.
                    local inset = CreateFrame("Frame", nil, menuBtn)
                    inset:SetPoint("TOPLEFT", 2, -2)
                    inset:SetPoint("BOTTOMRIGHT", -2, 2)
                    inset:SetFrameLevel(menuBtn:GetFrameLevel())
                    local btnBg = inset:CreateTexture(nil, "BACKGROUND", nil, -6)
                    btnBg:SetAllPoints()
                    GetFFD(menuBtn).gameMenuInset = inset
                    GetFFD(menuBtn).gameMenuButtonBg = btnBg
                    local highlight = menuBtn:CreateTexture(nil, "HIGHLIGHT")
                    highlight:SetAllPoints(inset)
                    highlight:SetColorTexture(1, 1, 1, 0.1)
                    local fontStr = menuBtn:GetFontString()
                    if fontStr then
                        local cuiFont = CludesUI.GetFontPath("blizzardSkin") or nil
                        local _, size, flags = fontStr:GetFont()
                        fontStr:SetFont(cuiFont or "Fonts\\FRIZQT__.TTF", (size or 14) - 2, flags or "")
                    end
                end
                ApplyButtonStyle(menuBtn)
            end
        end)
    end)
end

Inner.last = "Dialogs"
