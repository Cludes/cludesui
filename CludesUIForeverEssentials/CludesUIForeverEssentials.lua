if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials.lua  (WoW Forever only)
--  Essential tools for WoW Forever. Each feature lives in its own file, listed
--  after this one in the TOC; this file publishes the module.
-------------------------------------------------------------------------------
local ADDON_NAME, mod = ...
if
    not (
        CludesUI
        and CludesUI._ModuleNS
        and CludesUI._Pool
        and CludesUI.RegisterNumberFormatCallback
        and CludesUI.ApplyModuleFontFamily
        and CludesUI.ForeverTalentTrees
        and CludesUI.TalentTreeGrid
    )
then
    CUI_CLIENT_BLOCKED = true
    return
end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring (the threat meter redraws through the parent's RegisterNumberFormatCallback and takes its font families through ApplyModuleFontFamily; Classic Talents reads its trees through ForeverTalentTrees and TalentTreeGrid)
CludesUI._ModuleNS[ADDON_NAME] = mod -- LOD options files read this module ns via the registry

-- Lifecycle object (OnInitialize / OnEnable) for features that need one. No
-- per-profile DB: every feature so far keeps account-wide settings.
mod.addon = CludesUI.Lite.NewAddon(ADDON_NAME)

-------------------------------------------------------------------------------
--  Feature kit: settings and the login boot for every feature, plus placement
--  and the unlock element for the ones drawn on one frame of ours that unlock
--  mode places (Travel, Loot, Junk Items).
--  Settings are account-wide in CludesUIDB[dbKey]: Read() never creates the
--  table, so a feature nobody touches saves nothing; Cfg() is the write
--  accessor and Get() falls back to defaults. pos (point, relPoint, x, y) is
--  where unlock mode put the frame; defaultPos stands in until then.
-------------------------------------------------------------------------------
function mod.Feature(dbKey, defaultSet, defaultPos)
    local F, none = {}, {}
    local function Read()
        return CludesUIDB and CludesUIDB[dbKey] or none
    end
    local function Cfg()
        if not CludesUIDB then
            return {}
        end
        local c = CludesUIDB[dbKey]
        if not c then
            c = {}
            CludesUIDB[dbKey] = c
        end
        return c
    end
    local function Get(key)
        local val = Read()[key]
        if val == nil then
            return defaultSet[key]
        end
        return val
    end
    local function Enabled()
        return Get("enabled") == true
    end
    local function SavedPos()
        local place = Read().pos
        return place and place.point and place or defaultPos
    end
    -- A frame not built yet (nil) has nothing to place. snap: a CENTER point
    -- lands on the pixel grid for the frame's size, as unlock mode places it.
    local function Place(widget, snap)
        if not widget then
            return
        end
        local place = SavedPos()
        local posX, posY = place.x or 0, place.y or 0
        if snap and place.point == "CENTER" then
            local Pix = CludesUI.PP
            posX = Pix.SnapCenterForDim(posX, widget:GetWidth())
            posY = Pix.SnapCenterForDim(posY, widget:GetHeight())
        end
        widget:ClearAllPoints()
        widget:SetPoint(place.point, UIParent, place.relPoint or place.point, posX, posY)
    end
    F.Read, F.Cfg, F.Get, F.Enabled, F.Place = Read, Cfg, Get, Enabled, Place

    -- At login: apply(), then the unlock element when the feature has a frame
    -- (no u: nothing on screen).
    --   u.key, u.label, u.order
    --   u.frame(build)   the frame (nil until built); build builds it first
    -- By default the frame's width is its "width" setting, which unlock mode
    -- resizes, and its height follows its other settings:
    --   u.height()       the frame's height
    --   u.minWidth       the narrowest width unlock mode sets
    --   u.applyStyle()   lays the frame out again after a width change
    -- A frame whose settings fix its whole size gives u.size() instead; unlock
    -- mode then moves it but never resizes it:
    --   u.size()         the frame's width and height
    --   u.snap           every placement snaps its centre (see Place)
    --   u.noAnchorTarget, u.noSizeMatchTarget  as MakeUnlockElement takes them
    --   u.shown()        whether the frame is in use (default: the "enabled" setting)
    -- Nothing is built while the feature is off (the unlock core calls getFrame
    -- and applyPos for every element at each login).
    function F.Start(apply, unit)
        local boot = CreateFrame("Frame")
        boot:RegisterEvent("PLAYER_LOGIN")
        boot:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            apply()
            if not unit then
                return
            end
            local Shown = unit.shown or Enabled
            local e = {
                key = unit.key,
                label = unit.label,
                group = "Forever Tools",
                order = unit.order,
                noAnchorTarget = unit.noAnchorTarget,
                noSizeMatchTarget = unit.noSizeMatchTarget,
                isHidden = function()
                    return not Shown()
                end,
                getFrame = function()
                    return Shown() and unit.frame(true) or nil
                end,
                savePos = function(_, anchorPoint, relPoint, posX, posY)
                    if not anchorPoint then
                        return
                    end
                    Cfg().pos = { point = anchorPoint, relPoint = relPoint, x = posX, y = posY }
                    if not CludesUI._unlockActive then
                        Place(unit.frame(), unit.snap)
                    end
                end,
                loadPos = SavedPos,
                clearPos = function()
                    Cfg().pos = nil
                    Place(unit.frame(), unit.snap)
                end,
                applyPos = function()
                    if Shown() then
                        Place(unit.frame(true), unit.snap)
                    end
                end,
            }
            if unit.size then
                e.noResize = true
                e.getSize = unit.size
            else
                e.getSize = function()
                    return Get("width"), unit.height()
                end
                e.setWidth = function(_, wid)
                    Cfg().width = math.max(unit.minWidth, CludesUI.PP.Snap(wid))
                    unit.applyStyle()
                    if CludesUI._unlockActive and CludesUI.RepositionBarToMover then
                        CludesUI.RepositionBarToMover(unit.key)
                    end
                end
            end
            CludesUI:RegisterUnlockElements({ CludesUI.MakeUnlockElement(e) }, "CludesUIForeverEssentials")
        end)
    end
    return F
end

-------------------------------------------------------------------------------
--  Micro menu click layer (Classic Spellbook, Classic Talents)
-------------------------------------------------------------------------------
-- A plain button of ours over one of the game's micro buttons, for a window of
-- ours that stands in for the one the button opens. The game runs no secure
-- snippet wrapped on these buttons (they are not explicitly protected), so the
-- layer takes their left and right clicks instead. It is a child of the micro
-- button, so it shows, hides and fades with it; hover passes through to the
-- button (its tooltip and highlight), and so do the middle and side mouse
-- buttons, which Quick Keybind mode binds there. A click does nothing while
-- the game has the button disabled. Built out of combat, since its mouse
-- routing is blocked in combat on every frame; nil without the button.
function mod.MicroClickLayer(microName, onClick)
    local micro = _G[microName]
    if not micro or InCombatLockdown() then
        return nil
    end
    local layer = CreateFrame("Button", nil, micro)
    layer:SetAllPoints(micro)
    layer:SetFrameLevel(micro:GetFrameLevel() + 5)
    layer:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    layer:SetPropagateMouseMotion(true)
    layer:SetPassThroughButtons("MiddleButton", "Button4", "Button5")
    layer:SetScript("OnClick", function()
        if micro:IsEnabled() then
            onClick()
        end
    end)
    return layer
end

-------------------------------------------------------------------------------
--  Auctionator prices (Loot Feed, Junk Items)
-------------------------------------------------------------------------------
-- Auctionator's API, while that addon is loaded.
function mod.AuctionAPI()
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    return api and api.GetAuctionPriceByItemLink and api or nil
end

-- What Auctionator last saw one of the item listed for, when it has a price.
function mod.AuctionPrice(itemLink)
    local api = mod.AuctionAPI()
    if not api then
        return
    end
    local success, price = pcall(api.GetAuctionPriceByItemLink, "CludesUI", itemLink)
    if success and type(price) == "number" and price > 0 then
        return price
    end
end
