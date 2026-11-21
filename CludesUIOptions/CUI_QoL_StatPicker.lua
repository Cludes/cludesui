if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not CludesUI.IS_FOREVER then return end
-------------------------------------------------------------------------------
--  CUI_QoL_StatPicker.lua
--  WoW Forever: the Choose Stats window of the Secondary Stats cog. One
--  column per stat group of CludesUIQoL_ForeverStats.lua, All / None per
--  group, Check All / Uncheck All and Done. A click writes at once and the
--  block repaints live. Like the cog popups it dims nothing: it closes on a
--  click outside it, on Escape and with the options panel.
-------------------------------------------------------------------------------
local qns = CludesUI._ModuleNS["CludesUIQoL"]
if not qns then return end -- module disabled: no options page

-- Page reuse: frames this file builds go through the options frame pool
-- (CludesUI_FramePool.lua). The window is built once on the overlay layer,
-- which is no pool host, so its frames are plain new frames.
local CreateFrame = CludesUI._Pool.CreateFrame

local NUM_COLS, COL_W, COL_GAP = 3, 200, 18
local PAD, CONTENT_TOP = 24, 92
local HEADER_H, ITEM_H = 26, 24
local GRP_GAP, BOTTOM_H = 16, 66

local function IsShown(key)
    local hidden = CludesUI.QoLExtrasGet("secondaryStatsHidden")
    return not (type(hidden) == "table" and hidden[key])
end

-- One write and one repaint for any number of stats.
local function SetShown(stats, show)
    local old = CludesUI.QoLExtrasGet("secondaryStatsHidden")
    local hidden = {}
    if type(old) == "table" then
        for keyName, val in pairs(old) do
            hidden[keyName] = val
        end
    end
    for _, s in ipairs(stats) do
        hidden[s.key] = not show
    end
    CludesUI.QoLExtrasSet("secondaryStatsHidden", hidden)
    CludesUI._applySecondaryStats()
end

local panelFrame
local checks = {} -- one repaint function per stat row

local function RefreshAll()
    for _, apply in ipairs(checks) do
        apply()
    end
end

-- A text-only link (All / None / Check All) that brightens on hover.
local function Link(textValue, onClick)
    local widget = CreateFrame("Button", nil, panelFrame)
    local fontStr = CludesUI.MakeFont(widget, 12, "", 1, 1, 1, 0.5)
    fontStr:SetText(textValue)
    fontStr:SetPoint("CENTER")
    widget:SetSize(fontStr:GetStringWidth() + 6, 16)
    widget:SetScript("OnEnter", function() fontStr:SetTextColor(1, 1, 1, 0.9) end)
    widget:SetScript("OnLeave", function() fontStr:SetTextColor(1, 1, 1, 0.5) end)
    widget:SetScript("OnClick", function()
        onClick()
        RefreshAll()
    end)
    return widget
end

local function Build()
    local groups = qns.FvStats.groups
    local ACC = CludesUI.CLUDES_GREEN

    -- Groups wrap NUM_COLS to a line; each line is as tall as its longest group.
    local lineTop, cursorY = {}, CONTENT_TOP
    for first = 1, #groups, NUM_COLS do
        local num = 0
        for gi = first, math.min(first + NUM_COLS - 1, #groups) do
            num = math.max(num, #groups[gi].stats)
        end
        lineTop[#lineTop + 1] = cursorY
        cursorY = cursorY + HEADER_H + num * ITEM_H + GRP_GAP
    end

    panelFrame = CreateFrame("Frame", nil, CludesUI.OverlayParent())
    panelFrame:SetFrameStrata("FULLSCREEN_DIALOG") -- above the options panel and its popups
    panelFrame:SetSize(PAD * 2 + NUM_COLS * COL_W + (NUM_COLS - 1) * COL_GAP, cursorY - GRP_GAP + BOTTOM_H)
    panelFrame:SetScale(CludesUI.GetPopupScale())
    panelFrame:SetClampedToScreen(true)
    panelFrame:EnableMouse(true)
    panelFrame:Hide()
    local popFrame = CludesUI._popupFrames
    popFrame[#popFrame + 1] = { popup = panelFrame }
    CludesUI.PadHint(panelFrame, "nodepass")

    local panelBg = CludesUI.SolidTex(panelFrame, "BACKGROUND", 0.062, 0.070, 0.082, 1)
    panelBg:SetAllPoints()
    CludesUI.MakeRoundedBorder(panelFrame, 1, 1, 1, 0.15, panelBg)

    local title = CludesUI.MakeFont(panelFrame, 18, "", 1, 1, 1)
    title:SetPoint("TOP", panelFrame, "TOP", 0, -20)
    title:SetText(CludesUI.L("Stats to Show"))
    local subMenu = CludesUI.MakeFont(panelFrame, 12, "", 1, 1, 1, 0.45)
    subMenu:SetPoint("TOP", title, "BOTTOM", 0, -6)
    subMenu:SetText(CludesUI.L("Checked stats show in the on-screen block."))

    local all = {}
    for _, group in ipairs(groups) do
        for _, s in ipairs(group.stats) do
            all[#all + 1] = s
        end
    end
    local checkAll = Link(CludesUI.L("Check All"), function() SetShown(all, true) end)
    checkAll:SetPoint("TOPLEFT", panelFrame, "TOPLEFT", PAD, -62)
    local sep = CludesUI.SolidTex(panelFrame, "OVERLAY", 1, 1, 1, 0.18)
    sep:SetSize(1, 12)
    sep:SetPoint("LEFT", checkAll, "RIGHT", 10, 0)
    local uncheckAll = Link(CludesUI.L("Uncheck All"), function() SetShown(all, false) end)
    uncheckAll:SetPoint("LEFT", checkAll, "RIGHT", 20, 0)

    for gi, group in ipairs(groups) do
        local colX = PAD + ((gi - 1) % NUM_COLS) * (COL_W + COL_GAP)
        local grpY = -lineTop[math.floor((gi - 1) / NUM_COLS) + 1]

        local heading = CludesUI.MakeFont(panelFrame, 13, "", ACC.r, ACC.g, ACC.b)
        heading:SetPoint("TOPLEFT", panelFrame, "TOPLEFT", colX, grpY)
        heading:SetText(CludesUI.L(group.title))
        local none = Link(CludesUI.L("None"), function() SetShown(group.stats, false) end)
        none:SetPoint("TOPRIGHT", panelFrame, "TOPLEFT", colX + COL_W, grpY - 2)
        local allLink = Link(CludesUI.L("All"), function() SetShown(group.stats, true) end)
        allLink:SetPoint("RIGHT", none, "LEFT", -8, 0)
        local underline = CludesUI.SolidTex(panelFrame, "ARTWORK", ACC.r, ACC.g, ACC.b, 0.35)
        underline:SetSize(COL_W, 1)
        underline:SetPoint("TOPLEFT", panelFrame, "TOPLEFT", colX, grpY - HEADER_H + 8)

        for jdx, s in ipairs(group.stats) do
            local row = CreateFrame("Button", nil, panelFrame)
            row:SetSize(COL_W, ITEM_H)
            row:SetPoint("TOPLEFT", panelFrame, "TOPLEFT", colX, grpY - HEADER_H - (jdx - 1) * ITEM_H)
            local boxFrame, _, _, applyVisual = CludesUI.BuildCheckboxControl(row, row:GetFrameLevel() + 1)
            boxFrame:ClearAllPoints()
            boxFrame:SetPoint("LEFT", row, "LEFT", 0, 0)
            local labelFS = CludesUI.MakeFont(row, 12, "", 0.85, 0.85, 0.85)
            labelFS:SetPoint("LEFT", boxFrame, "RIGHT", 8, 0)
            labelFS:SetText(CludesUI.L(s.label))
            local function Apply() applyVisual(IsShown(s.key), row:IsMouseOver()) end
            checks[#checks + 1] = Apply
            local one = { s }
            row:SetScript("OnClick", function()
                SetShown(one, not IsShown(s.key))
                Apply()
            end)
            row:SetScript("OnEnter", function()
                labelFS:SetTextColor(1, 1, 1, 1)
                Apply()
            end)
            row:SetScript("OnLeave", function()
                labelFS:SetTextColor(0.85, 0.85, 0.85, 1)
                Apply()
            end)
        end
    end

    local done = CludesUI.MakeActionButton(
        panelFrame,
        CludesUI.EXPRESSWAY,
        CludesUI.L("Done"),
        ACC.r,
        ACC.g,
        ACC.b,
        { w = 200 }
    )
    done:SetPoint("BOTTOM", panelFrame, "BOTTOM", 0, 16)
    done:SetScript("OnClick", function() panelFrame:Hide() end)

    -- Closes on a click anywhere else: a global mouse-down listener held only
    -- while shown. Clicks fire on mouse up, so the press that opened it has
    -- already passed.
    panelFrame:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
    panelFrame:SetScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
    panelFrame:SetScript("OnEvent", function(self)
        if not self:IsMouseOver() then self:Hide() end
    end)
    panelFrame:EnableKeyboard(true)
    panelFrame:SetScript("OnKeyDown", function(self, key)
        self:SetPropagateKeyboardInput(key ~= "ESCAPE")
        if key == "ESCAPE" then self:Hide() end
    end)
    CludesUI._mainFrame:HookScript("OnHide", function() panelFrame:Hide() end)
    CludesUI.TrackOverlay(panelFrame)
end

function CludesUI._ShowStatPicker(anchor)
    if not panelFrame then Build() end
    panelFrame:ClearAllPoints()
    panelFrame:SetPoint("TOP", anchor, "BOTTOM", 0, -5)
    RefreshAll()
    panelFrame:Show()
    panelFrame:Raise()
end
