if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI_StyleChoicePopup.lua
--
--  First-install style picker. On the login AFTER the module picker's reload
--  (CludesUI_FirstInstall.lua stamps CludesUIDB.styleChoicePending in
--  its close path) one popup offers the three looks side by side, each with a
--  mock of what it means (the cards live in CludesUI_StyleCards.lua,
--  shared with the Style page header): the CludesUI style, the Blizzard
--  style or the Classic WoW UI style, or on the WoW Forever client also the
--  WoW Forever variant. The card of the look this session already renders
--  shows IN USE and stays lit as on the Style page; it keeps its hover and
--  closes the popup with nothing written, and so does Escape; any other card
--  sets every loaded module's Style flags at once through the Style page's
--  registry, then reloads. The default look (tagged DEFAULT) is the
--  CludesUI style, or WoW Forever on that client, whose card still sits
--  second, after CludesUI's; either is
--  normally the look in use (on WoW Forever the module picker applies it as
--  its reload is confirmed).
--  Once per install; an existing user never sees it, since only a first
--  install writes the stamp (the module picker's close, and on WoW Forever
--  also the first-install loader at ADDON_LOADED in CludesUI_FirstInstall.lua).
--  Global Settings > Style keeps every choice
--  reversible per module.
-------------------------------------------------------------------------------
local CludesUI = _G.CludesUI
if not CludesUI then return end
local CUI_HOST_ADDON = ...
local IS_STANDALONE = type(CUI_HOST_ADDON) == "string" and CUI_HOST_ADDON:find("Standalone") ~= nil
if IS_STANDALONE then return end

local PP = CludesUI.PanelPP
local MakeBorder = CludesUI.MakeBorder
local CLUDES_GREEN = CludesUI.CLUDES_GREEN

local function Stamp()
    if not CludesUIDB then CludesUIDB = {} end
    CludesUIDB.styleChoicePending = nil
end

-- Conflict-check handoff: while the picker is due this session the auto
-- addon-conflict check (CludesUI.lua) holds on _styleChoicePending, armed
-- at the parent's ADDON_LOADED below; every close that does not reload runs
-- it here (a reload's next session runs its own).
local function Release()
    if not CludesUI._styleChoicePending then return end
    CludesUI._styleChoicePending = nil
    if CludesUIDB and CludesUIDB.firstInstallPopupShown and CludesUI._RunConflictCheck then
        C_Timer.After(0.3, CludesUI._RunConflictCheck)
    end
end

-- Every loaded module to one look: the flags ride the Style page's own
-- registry (LoadOnDemand options), so one code path owns what "all modules"
-- means. False when the options addon cannot load. The module picker runs it
-- too on WoW Forever (CludesUI_FirstInstall.lua), as its reload's
-- pre-reload work. The caller reloads.
local function ApplyLook(styleKey)
    if not CludesUI.EnsureOptionsLoaded() then return false end
    local BS = CludesUI.BlizzStyle
    if not (BS and BS.ApplyAll) then return false end
    BS.ApplyAll(styleKey)
    return true
end
CludesUI.ApplyFirstInstallLook = ApplyLook

-- A look other than the one this session renders: the reload every style
-- change needs, asked for first in the click, then the look written as its
-- pre-reload work (RequestReload). When the options addon is turned off,
-- the popup (dimmer) closes on the chat hint instead of reloading.
local function ChooseOtherLook(styleKey, label, dimmer)
    Stamp()
    if C_AddOns.IsAddOnLoaded("CludesUIOptions")
        or C_AddOns.GetAddOnEnableState("CludesUIOptions") > 0 then
        CludesUI.RequestReload(nil, CludesUI.L("Style changed for this profile. A UI reload is needed to apply it."),
            function() ApplyLook(styleKey) end)
        return
    end
    CludesUI.Print("|cff4cc9f0CludesUI:|r " .. label .. " can be switched on under Global Settings > Style.")
    if dimmer then dimmer:Hide() end
    Release()
end

local function ShowStyleChoicePopup()
    if not (PP and MakeBorder and CLUDES_GREEN and CludesUI.BuildStyleCards) then
        Release()
        return
    end
    local FONT = CludesUI._font or CludesUI.EXPRESSWAY
        or "Interface\\AddOns\\CludesUI\\media\\fonts\\Barlow Condensed.ttf"
    local EG = CLUDES_GREEN
    -- Wide enough for the card row (four cards on the WoW Forever client).
    local POPUP_W, POPUP_H = math.max(700, CludesUI.STYLE_CARDS_W + 32), 480
    -- The DEFAULT card: CludesUI, or on the WoW Forever client WoW
    -- Forever, the look a fresh install there starts on.
    local defaultKey = CludesUI.IS_FOREVER and "forever" or "cui"
    -- The look this session renders, read from the modules: its card closes
    -- the popup with nothing written. The default while no styleable module
    -- is loaded; none while the loaded modules render different looks
    -- (every card applies then).
    local rendered = CludesUI.RenderedLook()
    local activeKey = rendered
    if activeKey == nil then activeKey = defaultKey elseif activeKey == false then activeKey = nil end
    local KeepLook, OnPick
    -- Escape keeps whatever renders: it never writes.
    local dimmer, popup = CludesUI.BuildPopupShell("CUIStyleChoice", {
        w = POPUP_W, h = POPUP_H, bump = 1.15, dimAlpha = 0.45,
        onEscape = function() KeepLook() end,
    })

    local eyebrow = popup:CreateFontString(nil, "OVERLAY")
    eyebrow:SetFont(FONT, 13, "")
    eyebrow:SetTextColor(EG.r, EG.g, EG.b, 0.9)
    PP.Point(eyebrow, "TOP", popup, "TOP", 0, -26)
    eyebrow:SetText(CludesUI.L("CHOOSE YOUR LOOK"))

    local title = popup:CreateFontString(nil, "OVERLAY")
    title:SetFont(FONT, 26, "")
    title:SetTextColor(1, 1, 1, 1)
    PP.Point(title, "TOP", eyebrow, "BOTTOM", 0, -6)
    title:SetText(CludesUI.L("How should CludesUI look?"))

    local desc = popup:CreateFontString(nil, "OVERLAY")
    desc:SetFont(FONT, 14, "")
    desc:SetTextColor(1, 1, 1, 0.5)
    desc:SetWidth(POPUP_W - 90)
    desc:SetJustifyH("CENTER")
    desc:SetWordWrap(true)
    PP.Point(desc, "TOP", title, "BOTTOM", 0, -10)
    desc:SetText(CludesUI.L("CludesUI's features work with every look. Change your mind any time under Global Settings > Style."))

    KeepLook = function()
        Stamp()
        dimmer:Hide()
        Release()
    end

    OnPick = function(styleKey)
        if styleKey == activeKey then
            KeepLook()
        elseif styleKey == "blizzard" then
            ChooseOtherLook("blizzard", "Blizzard Style", dimmer)
        elseif styleKey == "classic" then
            ChooseOtherLook("classic", "Classic WoW UI", dimmer)
        elseif styleKey == "forever" then
            ChooseOtherLook("forever", "WoW Forever", dimmer)
        else
            ChooseOtherLook("cui", "CludesUI Style", dimmer)
        end
    end

    -- The look cards (CludesUI_StyleCards.lua, shared with the Style page
    -- header): three, plus WoW Forever on that client, CludesUI's first.
    -- Set 10 below the description so the IN USE badge above a card clears it.
    local cards = CludesUI.BuildStyleCards(popup, -138, {
        buttonText = {
            cui = "Use CludesUI Style",
            blizzard = "Use Blizzard Style",
            classic = "Use Classic WoW UI",
            forever = "Use WoW Forever",
        },
        defaultKey = defaultKey,
        onPick = OnPick,
    })
    -- The look the loaded modules render: IN USE and lit, as on the Style page
    -- (no card while none is loaded or their looks differ). It stays pickable,
    -- hover included: clicking it keeps the look and closes the popup.
    local inUse = cards and type(rendered) == "string" and cards[rendered]
    if inUse then inUse:SetState(true, true, "In Use") end

    local footnote = popup:CreateFontString(nil, "OVERLAY")
    footnote:SetFont(FONT, 12, "")
    footnote:SetTextColor(1, 1, 1, 0.35)
    footnote:SetWidth(POPUP_W - 90)
    footnote:SetJustifyH("CENTER")
    PP.Point(footnote, "BOTTOM", popup, "BOTTOM", 0, 14)
    -- Names the cards that reload: every one but the active look's.
    if CludesUI.IS_FOREVER and activeKey == "forever" then
        footnote:SetText(CludesUI.L("CludesUI Style, Blizzard Style and Classic WoW UI reload the UI once to apply. Each module can be switched separately later."))
    elseif activeKey == "cui" and CludesUI.IS_FOREVER then
        footnote:SetText(CludesUI.L("WoW Forever, Blizzard Style and Classic WoW UI reload the UI once to apply. Each module can be switched separately later."))
    elseif activeKey == "cui" then
        footnote:SetText(CludesUI.L("Blizzard Style and Classic WoW UI reload the UI once to apply. Each module can be switched separately later."))
    else
        footnote:SetText(CludesUI.L("Every look but the one in use reloads the UI once to apply. Each module can be switched separately later."))
    end

    dimmer:Show()
end

CludesUI.ShowStyleChoicePopup = ShowStyleChoicePopup

-------------------------------------------------------------------------------
--  Trigger: the login after the module picker's reload, once.
-------------------------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" then
        if addonName ~= "CludesUI" then return end
        self:UnregisterEvent("ADDON_LOADED")
        -- Arm the conflict-check hold on the same conditions the login
        -- branch shows under (the first-install loader, earlier in the TOC,
        -- has already raised _firstInstallPending by now).
        if CludesUIDB and CludesUIDB.styleChoicePending
            and not CludesUI._firstInstallPending then
            CludesUI._styleChoicePending = true
        end
        return
    end
    self:UnregisterEvent("PLAYER_LOGIN")
    if not (CludesUIDB and CludesUIDB.styleChoicePending) then return end
    -- The picker itself is still due this session: it reloads, and its
    -- close path re-arms the stamp for the login after.
    if CludesUI._firstInstallPending then return end
    -- A registered external installer owns the first-run experience.
    if CludesUI._externalInstaller then Stamp(); Release(); return end
    local function TryShow()
        if not (CludesUIDB and CludesUIDB.styleChoicePending) then
            Release()
            return
        end
        ShowStyleChoicePopup()
    end
    C_Timer.After(0.8, TryShow)
end)
