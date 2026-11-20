if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- CUI_GroupFinder_Applications.lua: M+ applications bar in the rail, counts per
-- session, character and account.
-------------------------------------------------------------------------------
local ADDON_NAME, mod = ...
if CludesUI.HELD_BACK_ADDONS[ADDON_NAME] then
    return
end -- held back (CludesUIGroupFinder.lua)
local CM = CludesUI

local IsSecret, PlainString = CludesUI.IsSecret, CludesUI.PlainString
-- Realm the way UnitFullName returns it.
local function NormRealm(realm)
    realm = PlainString(realm)
    if not realm then
        return nil
    end
    realm = realm:gsub("[%s%-]", "")
    return realm ~= "" and realm or nil
end
local function MyRealm()
    return NormRealm(GetNormalizedRealmName and GetNormalizedRealmName()) or NormRealm(GetRealmName()) or "?"
end

local KEYS = { "applied", "accepted", "declined", "delisted", "cancelled", "invited" }
local SESSION_GAP = 300 -- relogging within 5 min keeps the session

local STATUS_KEY = {
    applied = "applied",
    declined = "declined",
    declined_full = "declined",
    timedout = "declined",
    declined_delisted = "delisted",
    cancelled = "cancelled",
    invited = "invited",
    inviteaccepted = "accepted",
}

-- Bar segments. Invites aren't shown, every invite counts as accepted.
local SEGMENTS = {
    { key = "accepted", cfg = "showAccepted", r = 0.35, g = 0.85, b = 0.40 },
    { key = "declined", cfg = "showDeclined", r = 0.95, g = 0.30, b = 0.30 },
    { key = "delisted", cfg = "showDelisted", r = 1.00, g = 0.60, b = 0.20 },
    { key = "cancelled", cfg = "showCancelled", r = 0.55, g = 0.55, b = 0.55 },
}
local SCOPES = { "session", "character", "account" }
local VALID_SCOPE = { session = true, character = true, account = true }

-- Tooltip labels and colour escapes, built on the first hover (the locale is
-- ready by then).
local tipText
local function TipText()
    if tipText then
        return tipText
    end
    tipText = {
        session = CludesUI.L("Session"),
        character = CludesUI.L("Character"),
        account = CludesUI.L("Account"),
        accepted = CludesUI.L("Accepted"),
        declined = CludesUI.L("Declined"),
        delisted = CludesUI.L("Delisted"),
        cancelled = CludesUI.L("Cancelled"),
        scopeHex = CM.HexColor(1, 0.82, 0.3),
        segHex = {},
    }
    for index, seg in ipairs(SEGMENTS) do
        tipText.segHex[index] = CM.HexColor(seg.r, seg.g, seg.b)
    end
    return tipText
end

-- Built-in bar textures plus SharedMedia's, built on first use.
local barTextures, barTexNames, barTexOrder
function mod.BarTextureTables()
    if not barTextures then
        barTextures, barTexNames, barTexOrder = CM.BuildBarTextureTables()
        CM.AppendSharedMediaTextures(barTexNames, barTexOrder, nil, barTextures)
    end
    return barTextures, barTexNames, barTexOrder
end

local function Cfg()
    return mod.AppsCfg()
end

local function Get(key, default)
    local cfg = Cfg()
    local val = cfg and cfg[key]
    if val == nil then
        return default
    end
    return val
end

local function On()
    return Get("enabled", false) == true
end

-- The picked bar texture's file, or nil for a flat colour.
local function TexturePath()
    local key = Get("texture", "none")
    if key == "none" then
        return nil
    end
    return CM.ResolveTexturePath((mod.BarTextureTables()), key)
end

local function ZeroCounts()
    local tbl = {}
    for _, k in ipairs(KEYS) do
        tbl[k] = 0
    end
    return tbl
end

local function Fill(tbl)
    for _, k in ipairs(KEYS) do
        tbl[k] = tonumber(tbl[k]) or 0
    end
    return tbl
end

local myKey
local function Store()
    local a = mod.AppCountsStore()
    if type(a.account) ~= "table" then
        a.account = ZeroCounts()
    end
    if type(a.chars) ~= "table" then
        a.chars = {}
    end
    if type(a.session) ~= "table" then
        a.session = ZeroCounts()
    end
    return a
end

local function Counts(scope)
    local a = Store()
    if scope == "account" then
        return Fill(a.account)
    end
    if scope == "session" then
        return Fill(a.session)
    end
    if not myKey then
        return ZeroCounts()
    end
    a.chars[myKey] = Fill(a.chars[myKey] or ZeroCounts())
    return a.chars[myKey]
end

-------------------------------------------------------------------------------
-- Card
-------------------------------------------------------------------------------
local cardFrame
local TITLE_SIZE = 12

local function Scope()
    local s = Get("scope", "character")
    return VALID_SCOPE[s] and s or "character"
end

-- Counts use the search box font (12 until it's set).
local function CountFont()
    local scrollBar = _G.LFGListFrame
        and _G.LFGListFrame.SearchPanel
        and _G.LFGListFrame.SearchPanel.SearchBox
    local filePath, size
    if type(scrollBar) == "table" and scrollBar.GetFont then
        filePath, size = scrollBar:GetFont()
    end
    if filePath and size and size > 0 then
        return filePath, size
    end
    return CM.GetFontPath(ADDON_NAME), 12
end

local tipLines = {} -- reused per hover
local function ShowTip(self)
    local T = TipText()
    local n = 1
    tipLines[1] = CludesUI.L("M+ Applications")
    for _, scope in ipairs(SCOPES) do
        local c = Counts(scope)
        tipLines[n + 1] = " "
        tipLines[n + 2] = T.scopeHex .. T[scope] .. "|r  " .. CludesUI.Lf("%d applied", c.applied)
        n = n + 2
        for index, seg in ipairs(SEGMENTS) do
            n = n + 1
            tipLines[n] = "   " .. T.segHex[index] .. T[seg.key] .. "|r  " .. c[seg.key]
        end
    end
    for index = #tipLines, n + 1, -1 do
        tipLines[index] = nil
    end
    CM.ShowWidgetTooltip(self, table.concat(tipLines, "\n"), { anchor = "right", justify = "LEFT" })
end
local function HideTip()
    CM.HideWidgetTooltip()
end

-- Where the search rows sit, in PVEFrame coordinates.
local function Place()
    local pve = _G.PVEFrame
    local inset = pve and pve.Inset
    if not (cardFrame and inset) then
        return
    end
    local r1, r2, size = -42, -57, 28
    if mod.Search_Rows then
        r1, r2, size = mod.Search_Rows()
    end
    local sp = _G.LFGListFrame and _G.LFGListFrame.SearchPanel
    local st, pt = sp and sp:GetTop(), pve:GetTop()
    local dy = (st and pt) and (st - pt) or 0
    local ref = _G.GroupFinderFrame and _G.GroupFinderFrame.groupButton1
    if type(ref) ~= "table" or not ref.GetLeft then
        ref = inset
    end
    local il, ir, pl = ref:GetLeft(), ref:GetRight(), pve:GetLeft()
    if not (il and ir and pl) then
        il, ir = inset:GetLeft(), inset:GetRight()
    end
    if not (il and ir and pl) then
        return
    end
    local pad = tonumber(mod.Cfg().padding) or 12
    local x1, x2 = il - pl + pad, ir - pl - pad
    cardFrame.box:ClearAllPoints()
    local ac = mod.AppsCfg and mod.AppsCfg()
    cardFrame.title:SetShown(not (ac and ac.showTitle == false))
    cardFrame.box:SetPoint("TOPLEFT", pve, "TOPLEFT", x1, dy + r2)
    cardFrame.box:SetPoint("TOPRIGHT", pve, "TOPLEFT", x2, dy + r2)
    cardFrame.box:SetHeight(size)
    cardFrame.title:ClearAllPoints()
    cardFrame.title:SetPoint("LEFT", pve, "TOPLEFT", x1, dy + r1)
end

local function Layout()
    if not cardFrame then
        return
    end
    local npath, nsize = CountFont()
    CM.ApplyModuleFont(cardFrame.title, nil, TITLE_SIZE, ADDON_NAME, "")
    -- The Premade Groups title, same size and colour as ours.
    local labelFS = _G.LFGListFrame
        and _G.LFGListFrame.CategorySelection
        and _G.LFGListFrame.CategorySelection.Label
    if labelFS and labelFS.GetFont then
        local lpath, lsize, lflags = labelFS:GetFont()
        if not cardFrame.lblSize then
            cardFrame.lblSize = lsize
        end
        if lpath then
            labelFS:SetFont(lpath, TITLE_SIZE, lflags)
        end
        local red, green, blue = labelFS:GetTextColor()
        if red then
            cardFrame.title:SetTextColor(red, green, blue, 1)
        end
    end
    local texPath = TexturePath()
    for index, seg in ipairs(SEGMENTS) do
        local t = cardFrame.segs[index]
        if texPath then
            t:SetTexture(texPath)
            t:SetVertexColor(seg.r, seg.g, seg.b, 1)
        else
            t:SetColorTexture(seg.r, seg.g, seg.b, 1)
            t:SetVertexColor(1, 1, 1, 1)
            t:SetTexCoord(0, 1, 0, 1)
        end
        CM.ApplyModuleFont(cardFrame.nums[index], npath, nsize, ADDON_NAME, "OUTLINE")
    end
    CM.ApplyModuleFont(cardFrame.empty, npath, nsize, ADDON_NAME, "OUTLINE")
    Place()
end

local shares = {} -- reused per paint
local function Refresh()
    if not (cardFrame and cardFrame:IsVisible()) then
        return
    end
    local c = Counts(Scope())
    -- Split the bar between the shown outcomes so it always fills.
    local sum = 0
    for index, seg in ipairs(SEGMENTS) do
        local val = c[seg.key]
        shares[index] = Get(seg.cfg, true) and val or 0
        sum = sum + shares[index]
    end
    local barFrame = cardFrame.bar
    local wid = barFrame:GetWidth() or 0
    local textured = TexturePath()
    local posX = 0
    for index, seg in ipairs(SEGMENTS) do
        local texture, num = cardFrame.segs[index], cardFrame.nums[index]
        local sw = (sum > 0) and (wid * shares[index] / sum) or 0
        texture:ClearAllPoints()
        texture:SetPoint("TOPLEFT", barFrame, "TOPLEFT", posX, 0)
        texture:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", posX, 0)
        texture:SetWidth(math.max(sw, 0.01))
        -- Each segment shows its slice of the texture so it reads as one bar.
        if textured and wid > 0 then
            texture:SetTexCoord(posX / wid, (posX + sw) / wid, 0, 1)
        end
        texture:SetShown(sw >= 0.5)
        num:SetFormattedText("%d", c[seg.key])
        num:ClearAllPoints()
        num:SetPoint("CENTER", texture, "CENTER", 0, 0)
        num:SetShown(sw >= 0.5 and (num:GetStringWidth() or 0) + 4 <= sw)
        posX = posX + sw
    end
    cardFrame.empty:SetShown(sum == 0) -- nothing counted yet
end

local BuildCardInto
local function BuildCard()
    if cardFrame then
        return cardFrame
    end
    local success, built = pcall(BuildCardInto)
    if success and built then
        cardFrame = built
    end
    if not success then
        geterrorhandler()(built)
    end
    return cardFrame
end

BuildCardInto = function()
    local owner = _G.GroupFinderFrame
    local pve = _G.PVEFrame
    if not (owner and pve and pve.Inset) then
        return nil
    end

    -- Build into a local first so a failure never leaves half a card.
    local cardFrame = CreateFrame("Frame", nil, owner)
    cardFrame:SetAllPoints(owner)
    cardFrame:SetFrameLevel(owner:GetFrameLevel() + 5)

    cardFrame.title = cardFrame:CreateFontString(nil, "OVERLAY")
    CM.ApplyModuleFont(cardFrame.title, nil, 12, ADDON_NAME, "")
    cardFrame.title:SetTextColor(1, 0.82, 0, 1)
    cardFrame.title:SetText(CludesUI.L("M+ Applications"))

    local box = CreateFrame("Frame", nil, cardFrame)
    box:EnableMouse(true)
    box:SetScript("OnEnter", ShowTip)
    box:SetScript("OnLeave", HideTip)
    local backdrop = box:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(0.2, 0.2, 0.2, 1)
    local S = mod.Skin()
    if S and S.AddBorder then
        S.AddBorder(box)
    else
        local red, green, blue, a = mod.ThemeBorder()
        CM.MakeBorder(box, red, green, blue, a)
    end
    cardFrame.box = box
    local px = CM.PP.mult
    local barFrame = CreateFrame("Frame", nil, box)
    barFrame:SetPoint("TOPLEFT", box, "TOPLEFT", px, -px)
    barFrame:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -px, px)
    cardFrame.bar = barFrame
    cardFrame.segs, cardFrame.nums = {}, {}
    for index = 1, #SEGMENTS do
        cardFrame.segs[index] = barFrame:CreateTexture(nil, "ARTWORK", nil, 1)
        local num = barFrame:CreateFontString(nil, "OVERLAY")
        CM.ApplyModuleFont(num, nil, 12, ADDON_NAME, "OUTLINE")
        num:SetTextColor(1, 1, 1, 1)
        num:SetJustifyH("CENTER")
        num:SetJustifyV("MIDDLE")
        cardFrame.nums[index] = num
    end
    cardFrame.empty = barFrame:CreateFontString(nil, "OVERLAY")
    CM.ApplyModuleFont(cardFrame.empty, nil, 12, ADDON_NAME, "OUTLINE")
    cardFrame.empty:SetTextColor(1, 1, 1, 0.6)
    cardFrame.empty:SetPoint("CENTER", barFrame, "CENTER", 0, 0)
    cardFrame.empty:SetText(CludesUI.L("N/A"))
    cardFrame.empty:Hide()
    barFrame:SetScript("OnSizeChanged", function()
        Refresh()
    end)
    return cardFrame
end

-- Only shown on the Dungeons search, the only category it counts.
local function InDungeonSearch()
    local sp = _G.LFGListFrame and _G.LFGListFrame.SearchPanel
    return sp and sp:IsShown() and sp.categoryID == (GROUP_FINDER_CATEGORY_ID_DUNGEONS or 2) or false
end

-- The status event is registered only while the bar is on.
local ev
local function SyncCountEvent()
    if not ev then
        return
    end
    if On() then
        ev:RegisterEvent("LFG_LIST_APPLICATION_STATUS_UPDATED")
    else
        ev:UnregisterEvent("LFG_LIST_APPLICATION_STATUS_UPDATED")
    end
end

local function Apply()
    if not mod.Enabled() then
        return
    end
    SyncCountEvent()
    local enabled = On()
    local wanted = enabled and InDungeonSearch()
    if wanted then
        BuildCard()
    end
    if cardFrame then
        cardFrame:SetShown(wanted)
        if wanted then
            Layout()
        elseif not enabled and cardFrame.lblSize then
            -- Off: title back to its own size.
            local labelFS = _G.LFGListFrame
                and _G.LFGListFrame.CategorySelection
                and _G.LFGListFrame.CategorySelection.Label
            local lpath, _, lflags = labelFS and labelFS:GetFont()
            if lpath then
                labelFS:SetFont(lpath, cardFrame.lblSize, lflags)
            end
        end
    end
    Refresh()
end
mod.ApplyApplications = Apply

-------------------------------------------------------------------------------
-- Counting
-------------------------------------------------------------------------------
local isMythicPlus = {} -- resultID -> is a Mythic+ group
local function LookUpMythicPlus(ident)
    local details = C_LFGList.GetSearchResultInfo(ident)
    if type(details) ~= "table" or IsSecret(details) or (canaccesstable and not canaccesstable(details)) then
        return nil
    end
    local acts = details.activityIDs
    local aid = (type(acts) == "table" and not IsSecret(acts)) and acts[1] or details.activityID
    if type(aid) ~= "number" or IsSecret(aid) then
        return nil
    end
    local ai = C_LFGList.GetActivityInfoTable(aid)
    if type(ai) ~= "table" or IsSecret(ai) or (canaccesstable and not canaccesstable(ai)) then
        return nil
    end
    local mp = ai.isMythicPlusActivity
    if IsSecret(mp) then
        return nil
    end
    return mp == true
end

local function Count(status, oldStatus, resultID)
    local key = STATUS_KEY[status]
    if type(resultID) ~= "number" or IsSecret(resultID) then
        return
    end
    if status == "applied" then
        if oldStatus == "applied" then
            return
        end
        isMythicPlus[resultID] = LookUpMythicPlus(resultID)
    elseif isMythicPlus[resultID] == nil then
        isMythicPlus[resultID] = LookUpMythicPlus(resultID)
    end
    local counted = isMythicPlus[resultID]
    if status ~= "applied" and status ~= "invited" then
        isMythicPlus[resultID] = nil
    end
    if not key or status == oldStatus or counted ~= true then
        return
    end
    local a = Store()
    local tbl = Fill(a.account)
    tbl[key] = tbl[key] + 1
    tbl = Fill(a.session)
    tbl[key] = tbl[key] + 1
    tbl = Counts("character")
    tbl[key] = tbl[key] + 1
    Refresh()
end

function mod.ResetApplications(scope)
    if not mod.Enabled() then
        return
    end
    local a = Store()
    if scope == "account" then
        a.account = ZeroCounts()
    elseif scope == "session" then
        a.session = ZeroCounts()
    elseif myKey then
        a.chars[myKey] = ZeroCounts()
    end
    Refresh()
end

local hooked = false
local function HookPVE()
    local pve = _G.PVEFrame
    if hooked or not pve then
        return
    end
    hooked = true
    -- Next frame, after the skin lays the window out.
    pve:HookScript("OnShow", function()
        C_Timer.After(0, Apply)
    end)
    if pve:IsShown() then
        C_Timer.After(0, Apply)
    end
    local sp = _G.LFGListFrame and _G.LFGListFrame.SearchPanel
    if sp then
        sp:HookScript("OnShow", function()
            C_Timer.After(0, Apply)
        end)
        sp:HookScript("OnHide", Apply)
    end
end

function mod.Apps_Enable()
    local name, realm = UnitFullName("player")
    name = PlainString(name)
    if name then
        myKey = name .. "-" .. (PlainString(realm) or MyRealm())
    end
    local a = Store()
    if time() - (tonumber(a.session.t) or 0) > SESSION_GAP then
        a.session = ZeroCounts()
    end
    -- Follow the search rows when they resize.
    if mod.Search_Layout then
        hooksecurefunc(mod, "Search_Layout", Apply)
    end
    ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_LOGOUT")
    ev:SetScript("OnEvent", function(self, evt, ...)
        if evt == "LFG_LIST_APPLICATION_STATUS_UPDATED" then
            -- Live check: a profile swap can turn the bar off before the next Apply.
            if On() then
                local ident, status, oldStatus = ...
                Count(PlainString(status), PlainString(oldStatus), ident)
            end
        elseif evt == "ADDON_LOADED" then
            if (...) == "Blizzard_GroupFinder" then
                HookPVE()
                self:UnregisterEvent("ADDON_LOADED")
            end
        elseif evt == "PLAYER_LOGOUT" then
            Store().session.t = time()
        end
    end)
    HookPVE()
    if not hooked then
        ev:RegisterEvent("ADDON_LOADED")
    end
    SyncCountEvent()
end
