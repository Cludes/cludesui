-- CludesUI_ClientGate.lua
-- Pre-12.1 client failsafe. MUST stay the FIRST file in the parent TOC.
--
-- This build targets WoW Midnight (12.1+) exclusively. If it ever loads on an
-- older client, running normally would be destructive: the migration pass
-- would rewrite settings into shapes the pre-12.1 addon cannot read, and the
-- DB layer would seed/transform tables against APIs that do not exist there.
-- The next logout would then persist that damage into the WTF files.
--
-- The failsafe: on a pre-12.1 client this file sets CUI_CLIENT_BLOCKED, and
-- line 1 of EVERY suite file returns immediately when that flag is set. No
-- DB is created, no migration runs, no SavedVariables global is ever read or
-- written -- WoW loads each WTF file into its global and writes the same
-- untouched table back at logout, a lossless round trip. The only thing that
-- runs is the popup below telling the user to go back to the pre-12.1
-- release. Reverting restores the addon with settings exactly as they were.
--
-- Fail-open by design: if the interface number cannot be read as a number,
-- the suite runs normally -- the failsafe must never break a healthy client.
-- On 12.1+ this file is two comparisons and exits; no globals, no frames.

local iface = select(4, GetBuildInfo())
if type(iface) ~= "number" then return end

-- WoW Forever (Blizzard game type "camelot"): the 12.1 engine with vanilla
-- content, reporting a 1.60+ toc (16001). Classic Era reports 115xx and
-- retail 12xxxx, so the ranges never meet. Flagged for the suite before any
-- other file runs (CludesUI.IS_FOREVER, CludesUI_Lite.lua); nothing is
-- blocked there.
if iface >= 16000 and iface < 20000 then
    CUI_CLIENT_FOREVER = true
    return
end
if iface >= 120100 then return end

CUI_CLIENT_BLOCKED = true

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()

    local p = CreateFrame("Frame", "CUIClientGatePopup", UIParent)
    p:SetSize(480, 170)
    p:SetPoint("CENTER", 0, 140)
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:EnableMouse(true)

    local backdrop = p:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(0.062, 0.050, 0.039, 0.97)

    -- 1px accent border (no dependencies -- the shared border kit is gated).
    local function AddFrameEdge(point1, point2, wid, hgt)
        local tex = p:CreateTexture(nil, "BORDER")
        tex:SetColorTexture(0.30, 0.79, 0.94, 0.9)
        tex:SetPoint(point1)
        tex:SetPoint(point2)
        if wid then tex:SetWidth(wid) end
        if hgt then tex:SetHeight(hgt) end
        return tex
    end
    AddFrameEdge("TOPLEFT", "TOPRIGHT", nil, 1)
    AddFrameEdge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    AddFrameEdge("TOPLEFT", "BOTTOMLEFT", 1, nil)
    AddFrameEdge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)

    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("CludesUI")
    title:SetTextColor(0.30, 0.79, 0.94)

    local body = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOP", title, "BOTTOM", 0, -12)
    body:SetWidth(430)
    body:SetJustifyH("CENTER")
    body:SetText(
        "This version of CludesUI is built for the Midnight 12.1 patch and has been disabled on this game version.|n|nYour saved settings are safe and untouched. Please install the previous CludesUI release until 12.1 launches."
    )

    local button = CreateFrame("Button", nil, p)
    button:SetSize(110, 26)
    button:SetPoint("BOTTOM", 0, 14)
    local bbg = button:CreateTexture(nil, "BACKGROUND")
    bbg:SetAllPoints()
    bbg:SetColorTexture(0.30, 0.79, 0.94, 0.85)
    local bl = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    bl:SetPoint("CENTER")
    bl:SetText("Okay")
    bl:SetTextColor(0, 0, 0)
    button:SetScript("OnEnter", function() bbg:SetColorTexture(0.30, 0.79, 0.94, 1) end)
    button:SetScript("OnLeave", function() bbg:SetColorTexture(0.30, 0.79, 0.94, 0.85) end)
    button:SetScript("OnClick", function() p:Hide() end)

    tinsert(UISpecialFrames, "CUIClientGatePopup")
end)
