if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  Quest log rows on WoW Forever
--
--  The Map & Quest Log pack (WindowPacks.lua, key "worldmap") leaves the pooled
--  quest rows stock. On Forever that keeps three gold pieces in the CludesUI
--  look: the track checkbox on each quest (questlog-icon-ticksquare plus a
--  yellow tick), the headers' +/- buttons and the "Quests: N/M" box. This
--  repaints them, visual only (alpha, colour and child textures, no scripts
--  touched): a flat dark square with a 1 px border and an accent tick, a white
--  +/-, and a flat box with white text. Forever only.
--------------------------------------------------------------------------------
local _, mod = ...
local CUI = _G.CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
local Skin = mod.WSkin
if not (Skin and Skin.RegisterWindow and Skin.GetFFD) then return end

local QLF = {}
mod._QuestLogForever = QLF

-- The track checkbox: the gold square and its highlight go (the template's
-- unnamed textures); a flat square and the accent tick take their place.
function QLF.Checkbox(box)
    if not box or box:IsForbidden() then return end
    local data = Skin.GetFFD(box)
    if not data.cuiBox then
        data.cuiBox = true
        local regions = { box:GetRegions() }
        for i = 1, #regions do
            local r = regions[i]
            if r ~= box.CheckMark and r.SetAlpha then r:SetAlpha(0) end
        end
        local fill = box:CreateTexture(nil, "BACKGROUND", nil, 1)
        fill:SetPoint("CENTER")
        fill:SetSize(12, 12)
        fill:SetColorTexture(0.08, 0.08, 0.08, 0.95)
        data.fill = fill
        local edge = CreateFrame("Frame", nil, box)
        edge:SetAllPoints(fill)
        edge:SetFrameLevel(box:GetFrameLevel())
        Skin.AddBorder(edge, 0.3, 0.3, 0.3, 1)
        data.edge = edge
        local hover = box:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints(fill)
        hover:SetColorTexture(1, 1, 1, 0.12)
    end
    local tick = box.CheckMark
    if tick then
        tick:SetDesaturated(true)
        tick:SetVertexColor(Skin.AccentBarColor())
    end
end

-- A header's +/-: white instead of gold (SetAtlas on each toggle keeps the
-- colour, the hook covers a pooled button that never painted).
local function WhiteIcon(button)
    local icon = button and button.Icon
    if not icon then return end
    icon:SetDesaturated(true)
    icon:SetVertexColor(0.9, 0.9, 0.9, 1)
end
function QLF.Collapse(button)
    if not button or button:IsForbidden() then return end
    local data = Skin.GetFFD(button)
    if not data.cuiCollapse and button.UpdateCollapsedState then
        data.cuiCollapse = true
        hooksecurefunc(button, "UpdateCollapsedState", WhiteIcon)
    end
    WhiteIcon(button)
end

-- "Quests: N/M": the input-box art goes, a flat box and white text.
function QLF.Count(frame)
    if not frame or frame:IsForbidden() then return end
    local data = Skin.GetFFD(frame)
    if not data.cuiCount then
        data.cuiCount = true
        for _, k in ipairs({ "Left", "Middle", "Right" }) do
            if frame[k] then frame[k]:SetAlpha(0) end
        end
        local fill = frame:CreateTexture(nil, "BACKGROUND")
        fill:SetAllPoints()
        fill:SetColorTexture(0.08, 0.08, 0.08, 0.95)
        Skin.AddBorder(frame, 0.25, 0.25, 0.25, 1)
    end
    local text = _G.QuestLogQuestCount
    if text then Skin.White(text) end
end

local function EachActive(pool, fn)
    if not (pool and pool.EnumerateActive) then return end
    pcall(function()
        for frame in pool:EnumerateActive() do
            fn(frame)
        end
    end)
end

function QLF.Rows()
    if Skin.GetStyle("worldmap") == "off" then return end
    local scroll = _G.QuestScrollFrame
    if not scroll then return end
    EachActive(scroll.titleFramePool, function(row) QLF.Checkbox(row.Checkbox) end)
    for _, key in ipairs({ "headerFramePool", "campaignHeaderMinimalFramePool", "covenantCallingsHeaderFramePool" }) do
        EachActive(scroll[key], function(header) QLF.Collapse(header.CollapseButton) end)
    end
    QLF.Count(_G.QuestLogCount)
end

local hooked
Skin.RegisterWindow({
    key = "worldmap",
    addons = { Blizzard_WorldMap = true },
    apply = function()
        QLF.Rows()
        if not hooked and type(_G.QuestLogQuests_Update) == "function" then
            hooked = true
            hooksecurefunc("QuestLogQuests_Update", QLF.Rows)
        end
    end,
})
