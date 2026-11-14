if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then
    return
end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_DruidMana.lua  (WoW Forever only)
--  Mana Bar: a druid's mana while in a form that shows rage or energy, and
--  for any mana user who turns on Always Show. A thin line under it counts
--  down the five-second rule: after a spell that costs mana, spirit regen
--  stops for five seconds. The rule starts when your mana drops (a spell
--  was paid for); regen ticks and potions only ever raise it.
-------------------------------------------------------------------------------
local _, module = ...

local DEFAULTS = { enabled = false, width = 180, height = 10, fiveSecond = true, always = false }
local F = module.Feature("druidMana", DEFAULTS, { point = "CENTER", relPoint = "CENTER", x = 0, y = -240 })
local Get, Enabled = F.Get, F.Enabled

local MANA = Enum.PowerType.Mana
local RULE = 5
local LINE_H = 3

local holderFrame, bar, line, textValue
local lastMana, ruleEnds

local function Font()
    return CludesUI.GetFontPath("essentials")
end
local function Secret(val)
    return issecretvalue and issecretvalue(val)
end

local function UsesMana()
    local max = UnitPowerMax("player", MANA)
    return not Secret(max) and max and max > 0
end

-- Druid in a form whose bar is not mana, or Always Show for a mana user.
local function Wanted()
    if not (Enabled() and UsesMana()) then
        return false
    end
    if CludesUI._unlockActive or Get("always") then
        return true
    end
    local _, class = UnitClass("player")
    return class == "DRUID" and UnitPowerType("player") ~= MANA
end

local function Build()
    if holderFrame then
        return holderFrame
    end
    holderFrame = CreateFrame("Frame", "CludesUIManaBar", UIParent)
    bar = CreateFrame("StatusBar", nil, holderFrame)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    local c = PowerBarColor and PowerBarColor.MANA or { r = 0, g = 0.55, b = 1 }
    bar:GetStatusBarTexture():SetVertexColor(c.r, c.g, c.b)
    CludesUI.Kit.Panel(bar, 0.85)
    textValue = bar:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(textValue, 10, "essentials")
    textValue:SetPoint("CENTER")
    line = CreateFrame("StatusBar", nil, holderFrame)
    line:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    line:GetStatusBarTexture():SetVertexColor(1, 1, 1, 0.9)
    line:SetMinMaxValues(0, RULE)
    line:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -1)
    line:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -1)
    line:SetHeight(LINE_H)
    line:Hide()
    return holderFrame
end

local function Layout()
    if not holderFrame then
        return
    end
    holderFrame:SetSize(Get("width"), Get("height") + LINE_H + 1)
    bar:SetHeight(Get("height"))
end

local function UpdateMana()
    if not holderFrame then
        return
    end
    if not Wanted() then
        holderFrame:Hide()
        return
    end
    holderFrame:Show()
    local current, max = UnitPower("player", MANA), UnitPowerMax("player", MANA)
    bar:SetMinMaxValues(0, max)
    bar:SetValue(current)
    if Secret(current) or Secret(max) then
        textValue:SetText("")
        lastMana = nil
        return
    end
    textValue:SetText(("%d / %d"):format(current, max))
    if Get("fiveSecond") and lastMana and current < lastMana then
        ruleEnds = GetTime() + RULE
        line:Show()
    end
    lastMana = current
end

local function Tick()
    if not (ruleEnds and line) then
        return
    end
    local leftX = ruleEnds - GetTime()
    if leftX <= 0 or not Get("fiveSecond") then
        ruleEnds = nil
        line:Hide()
        return
    end
    line:SetValue(leftX)
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", UpdateMana)
local ticker

local function Apply()
    if Enabled() then
        Build()
        Layout()
        ev:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
        ev:RegisterUnitEvent("UNIT_MAXPOWER", "player")
        ev:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
        ev:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
        ev:RegisterEvent("PLAYER_ENTERING_WORLD")
        if not ticker then
            ticker = C_Timer.NewTicker(0.05, Tick)
        end
        if not CludesUI._unlockActive then
            F.Place(holderFrame)
        end
    else
        ev:UnregisterAllEvents()
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
        if holderFrame then
            holderFrame:Hide()
        end
    end
    UpdateMana()
end

CludesUI._DruidMana = { Get = Get, Read = F.Read, Cfg = F.Cfg, Apply = Apply }

F.Start(Apply, {
    key = "CUI_ManaBar",
    label = "Mana Bar",
    order = 737,
    frame = function(build)
        if build then
            Build()
            Layout()
            UpdateMana()
        end
        return holderFrame
    end,
    size = function()
        return Get("width"), Get("height") + LINE_H + 1
    end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})
