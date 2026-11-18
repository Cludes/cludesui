if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIQoL_Shifter.lua
--  Shift+drag to permanently reposition Blizzard panels.
--  Ctrl+drag for a temporary move that resets when the panel closes.
-------------------------------------------------------------------------------
local GetFFD = CludesUI._GetFFD
local mod = select(2, ...)

-- Temporary positions (per-frame, cleared on hide, not persisted)
local tempPos = {}

-- Temporary scales (per-frame, cleared on hide, not persisted)
local tempScale = {}

-- Every hooked frame, for the scroll-wheel overlay's mouseover targeting
local hookedFrames = {}

-- Forward-declare; created in the event-driven initialization section below
local watcher

-------------------------------------------------------------------------------
--  Frame registry
-------------------------------------------------------------------------------
local PRELOADED = {
    "ContainerFrameCombinedBags",
    "CharacterFrame",
    "FriendsFrame",
    "PVEFrame",
    "DressUpFrame",
    "BankFrame",
    "MailFrame",
    "OpenMailFrame", -- the window of one opened mail
    "GossipFrame",
    "QuestFrame",
    "MerchantFrame",
    "AddonList",
    "ChatConfigFrame",
    "ItemTextFrame",
    "LFGDungeonReadyDialog",
    "GuildInviteFrame",
    "TabardFrame",
    "GuildRegistrarFrame",
    "SettingsPanel", -- the game options (Blizzard_Settings_Shared, loaded at startup)
}

local ADDON_FRAMES = {
    ["Blizzard_AchievementUI"] = { "AchievementFrame" },
    ["Blizzard_AlliedRacesUI"] = { "AlliedRacesFrame" },
    ["Blizzard_ArchaeologyUI"] = { "ArchaeologyFrame" },
    ["Blizzard_ArtifactUI"] = { "ArtifactFrame" },
    ["Blizzard_AuctionHouseUI"] = { "AuctionHouseFrame" },
    ["Blizzard_BlackMarketUI"] = { "BlackMarketFrame" },
    ["Blizzard_Calendar"] = { "CalendarFrame", "CalendarViewEventFrame" },
    ["Blizzard_ChallengesUI"] = { "ChallengesKeystoneFrame" },
    ["Blizzard_ChromieTimeUI"] = { "ChromieTimeFrame" },
    ["Blizzard_ClassTalentUI"] = { "ClassTalentFrame" },
    ["Blizzard_Collections"] = { "CollectionsJournal", "WardrobeFrame" },
    ["Blizzard_Communities"] = { "CommunitiesFrame" },
    ["Blizzard_CooldownViewer"] = { "CooldownViewerSettings" },
    ["Blizzard_EncounterJournal"] = { "EncounterJournal" },
    ["Blizzard_ExpansionLandingPage"] = { "ExpansionLandingPage" },
    ["Blizzard_FlightMap"] = { "FlightMapFrame" },
    ["Blizzard_GenericTraitUI"] = { "GenericTraitFrame" },
    ["Blizzard_GroupFinder_VanillaStyle"] = { "LFGParentFrame" }, -- WoW Forever's group finder
    ["Blizzard_GuildBankUI"] = { "GuildBankFrame" },
    ["Blizzard_GuildControlUI"] = { "GuildControlUI" },
    ["Blizzard_InspectUI"] = { "InspectFrame" },
    ["Blizzard_ItemInteractionUI"] = { "ItemInteractionFrame" },
    ["Blizzard_ItemSocketingUI"] = { "ItemSocketingFrame" },
    ["Blizzard_ItemUpgradeUI"] = { "ItemUpgradeFrame" },
    ["Blizzard_LegacySystem"] = { "LegacySystemFrame" }, -- WoW Forever's Legacy window
    ["Blizzard_MacroUI"] = { "MacroFrame" },
    ["Blizzard_MajorFactions"] = { "MajorFactionRenownFrame" },
    ["Blizzard_PlayerSpells"] = { "PlayerSpellsFrame" },
    ["Blizzard_Professions"] = { "ProfessionsFrame" },
    ["Blizzard_ProfessionsBook"] = { "ProfessionsBookFrame" },
    ["Blizzard_ProfessionsCustomerOrders"] = { "ProfessionsCustomerOrdersFrame" },
    ["Blizzard_ScrappingMachineUI"] = { "ScrappingMachineFrame" },
    ["Blizzard_SocialUI"] = { "SocialUIFrame" },
    ["Blizzard_StableUI"] = { "StableFrame", "PetStableFrame" }, -- PetStableFrame: WoW Forever's
    ["Blizzard_TokenUI"] = { "CurrencyTransferMenu" },
    ["Blizzard_TrainerUI"] = { "ClassTrainerFrame" },
    ["Blizzard_TradeSkillUI"] = { "TradeSkillFrame" },
    ["Blizzard_Transmog"] = { "TransmogFrame" },
    ["Blizzard_WeeklyRewards"] = { "WeeklyRewardsFrame" },
    ["Blizzard_WorldMap"] = { "WorldMapFrame" },
    -- Midnight Housing
    ["Blizzard_HousingDashboard"] = { "HousingDashboardFrame" },
    ["Blizzard_HousingCornerstone"] = { "HousingCornerstonePurchaseFrame" },
    ["Blizzard_HousingHouseFinder"] = { "HouseFinderFrame" },
    ["Blizzard_HousingHouseSettings"] = { "HousingHouseSettingsFrame" },
    ["Blizzard_HousingBulletinBoard"] = { "HousingBulletinBoardFrame" },
    ["Blizzard_HousingModelPreview"] = { "HousingModelPreviewFrame" },
    -- Delves
    ["Blizzard_DelvesCompanionConfigurationFrame"] = {
        "DelvesCompanionConfigurationFrame",
        "DelvesCompanionAbilityListFrame",
    },
    ["Blizzard_DelvesDifficultyPicker"] = { "DelvesDifficultyPickerFrame" },
}

-- For these frames the drag target is a child header element, not the frame
-- itself (avoids fighting model-rotate or interior click regions).
local DRAG_HEADERS = {
    ["WorldMapFrame"] = "WorldMapTitleButton",
}

-- Extra drag handles layered ON TOP of the frame body. Used when a
-- mouse-enabled child sits over the frame and would otherwise swallow the
-- drag (e.g. the Achievement frame's floating points header). Values resolve
-- to a child frame: either a global name or a function(frame) -> child, or a
-- list of global names.
local EXTRA_DRAG_TARGETS = {
    ["AchievementFrame"] = function(widget)
        return widget.Header or _G["AchievementFrameHeader"]
    end,
    ["ContainerFrameCombinedBags"] = function(widget)
        return widget.TitleContainer or _G["ContainerFrameCombinedBags"]
    end,
    -- WoW Forever's group finder: each tab is a full window laid over the parent
    ["LFGParentFrame"] = { "LFGBrowseFrame", "LFGListingFrame", "LFGWhoListFrame" },
}

-- Blizzard windows that normally dock beside CharacterFrame (Item Upgrade, Transmog,
-- Item Socketing, Merchant -- covers vendors like the Crest Exchange -- plus Friends,
-- Guild/Communities, and Professions, which normally sit to CharacterFrame's left with
-- CharacterFrame staying put). See the docking hook in HookFrame for why and how.
--
-- PVEFrame is deliberately NOT here: CludesUIBlizzardSkin_GroupFinder.lua owns that
-- pairing instead, docking CharacterFrame beside PVEFrame (rather than the reverse)
-- with room-detection that also accounts for third-party companion panels bolted onto
-- PVEFrame. Both mechanisms at once would fight: this one's plain room check knows
-- nothing of such a panel, so it could re-dock PVEFrame right on top of it the moment
-- CharacterFrame got any saved/temp Shifter position at all. PVEFrame being protected
-- already skips this module's strata/Raise writes (see the `else` branch below), so
-- leaving it entirely to GroupFinder.lua loses nothing.
local DOCKING_COMPANIONS = {
    ItemUpgradeFrame = true,
    TransmogFrame = true,
    ItemSocketingFrame = true,
    MerchantFrame = true,
    FriendsFrame = true,
    SocialUIFrame = true,
    CommunitiesFrame = true,
    ProfessionsFrame = true,
    ProfessionsBookFrame = true,
    WorldMapFrame = true,
    HousingDashboardFrame = true,
    EncounterJournal = true,
}

-- Unprotected windows that take the protected path all the same (Secured):
-- an insecure SetMovable, SetClampedToScreen, StartMoving, SetPoint, SetScale,
-- strata or Raise write of ours taints the window's tree, as it did PVEFrame's,
-- and the Guild & Communities list hands secret club data to a call allowed
-- only untainted (C_Club.SetAvatarTexture, in Mythic+ and raids).
local SECURE_PATH = { CommunitiesFrame = true }

-- Windows whose strata is never changed when lifted over a moved CharacterFrame
-- (Raise only): a strata change leaves the Adventure Guide's boss loot list blank.
local NO_STRATA_LIFT = { EncounterJournal = true }

-- Whether a hooked window takes the protected path: secure positioning and
-- scaling, the cursor-delta drag, position-only docking, never moved in combat.
local function Secured(widget)
    return widget:IsProtected() or GetFFD(widget)._shSecure == true
end

-------------------------------------------------------------------------------
--  Position helpers
-------------------------------------------------------------------------------
local function IsEnabled()
    return CludesUIDB and CludesUIDB.shifterEnabled or false
end

local function GetSavedPos(frameName)
    local store = CludesUIDB
    return store and store.shifterPositions and store.shifterPositions[frameName]
end

local function SavePos(frameName, anchorPoint, relPoint, posX, posY)
    if not CludesUIDB then
        CludesUIDB = {}
    end
    if not CludesUIDB.shifterPositions then
        CludesUIDB.shifterPositions = {}
    end
    CludesUIDB.shifterPositions[frameName] = {
        point = anchorPoint,
        relPoint = relPoint,
        x = posX,
        y = posY,
    }
    CludesUI:RefreshPage(true)
end

local function GetSavedScale(frameName)
    local store = CludesUIDB
    return store and store.shifterScales and store.shifterScales[frameName]
end

local function SaveScale(frameName, scale)
    if not CludesUIDB then
        CludesUIDB = {}
    end
    if not CludesUIDB.shifterScales then
        CludesUIDB.shifterScales = {}
    end
    CludesUIDB.shifterScales[frameName] = scale
end

-------------------------------------------------------------------------------
--  Secure repositioning (for PROTECTED frames)
--
--  A plain frame:SetPoint() / StartMoving() / SetMovable() called from insecure
--  addon code TAINTS the frame's execution. That is invisible on most panels,
--  but PVEFrame parents the LFGList applicant viewer, which does secret-value
--  comparisons in 12.0 -- a tainted tree throws "attempt to compare a secret
--  number" there. So protected frames are NEVER touched with those calls; we
--  run ClearAllPoints/SetPoint inside a SecureHandler restricted-environment
--  snippet instead, which executes securely and never taints the frame.
--  Parented to UIParent so self:GetParent() inside the snippet IS UIParent.
-------------------------------------------------------------------------------
local positioner = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
local function SecureSetPoint(widget, anchorPoint, relPoint, posX, posY)
    if InCombatLockdown() then
        return false
    end
    positioner:SetFrameRef("f", widget)
    positioner:SetAttribute("p", anchorPoint)
    positioner:SetAttribute("rp", relPoint)
    positioner:SetAttribute("x", posX)
    positioner:SetAttribute("y", posY)
    positioner:Execute([[
        local f = self:GetFrameRef("f")
        if not f then return end
        f:ClearAllPoints()
        f:SetPoint(self:GetAttribute("p"), self:GetParent(), self:GetAttribute("rp"), self:GetAttribute("x"), self:GetAttribute("y"))
    ]])
    return true
end

-- The same write, anchored to the frame's own parent instead of UIParent.
-- "$parent" and not a frame ref: a relative frame handed in by ref must be
-- explicitly protected (RestrictedFrames.lua), and a parent that is only
-- protected through its children is not.
local function SecureSetPointParent(widget, anchorPoint, relPoint, posX, posY)
    if InCombatLockdown() then
        return false
    end
    positioner:SetFrameRef("f", widget)
    positioner:SetAttribute("p", anchorPoint)
    positioner:SetAttribute("rp", relPoint)
    positioner:SetAttribute("x", posX)
    positioner:SetAttribute("y", posY)
    positioner:Execute([[
        local f = self:GetFrameRef("f")
        if not f then return end
        f:ClearAllPoints()
        f:SetPoint(self:GetAttribute("p"), "$parent", self:GetAttribute("rp"), self:GetAttribute("x"), self:GetAttribute("y"))
    ]])
    return true
end

-- Where a point sits in a box, as fractions of its width and height from the
-- bottom left corner.
local function PointFrac(p)
    local posX = p:find("LEFT") and 0 or (p:find("RIGHT") and 1 or 0.5)
    local posY = p:find("TOP") and 1 or (p:find("BOTTOM") and 0 or 0.5)
    return posX, posY
end

-- Whether a window placed at its saved position would overlap CharacterFrame
-- (screen-absolute units, so Shifter scaling on either frame is accounted for).
local function SavedPosOverlaps(widget, place, castFrame)
    local effScale, cs = widget:GetEffectiveScale() or 1, castFrame:GetEffectiveScale() or 1
    local uiScale = UIParent:GetEffectiveScale() or 1
    local cl, cr, callback, ct =
        castFrame:GetLeft(), castFrame:GetRight(), castFrame:GetBottom(), castFrame:GetTop()
    if not (cl and cr and callback and ct and place.point) then
        return false
    end
    local wid, hgt = (widget:GetWidth() or 0) * effScale, (widget:GetHeight() or 0) * effScale
    local rx, ry = PointFrac(place.relPoint or place.point)
    local px, py = PointFrac(place.point)
    local leftX = rx * UIParent:GetWidth() * uiScale + (place.x or 0) * effScale - px * wid
    local bottom = ry * UIParent:GetHeight() * uiScale + (place.y or 0) * effScale - py * hgt
    return leftX < cr * cs and leftX + wid > cl * cs and bottom < ct * cs and bottom + hgt > callback * cs
end

-- Offset from one point of a w x h box to another: a mover saves where one
-- point of its box is, and the frame it places may hang from another (so a
-- frame that grows keeps that edge where the player put it).
local function AnchorShift(anchorPoint, anchor, wid, hgt)
    local px, py = PointFrac(anchorPoint)
    local ax, ay = PointFrac(anchor)
    return (ax - px) * wid, (ay - py) * hgt
end

local function ApplyPosition(widget, frameName)
    if InCombatLockdown() and Secured(widget) then
        return
    end
    local place = tempPos[widget] or GetSavedPos(frameName)
    if not place or not place.point then
        return
    end
    local frameData = GetFFD(widget)
    frameData._shIgnoreSP = true
    if Secured(widget) then
        SecureSetPoint(widget, place.point, place.relPoint, place.x, place.y)
    else
        widget:ClearAllPoints()
        widget:SetPoint(place.point, UIParent, place.relPoint, place.x, place.y)
    end
    frameData._shIgnoreSP = false
end

-------------------------------------------------------------------------------
--  Scaling (Shift+Scroll = permanent, Ctrl+Scroll = temporary)
--
--  Same protection split as positioning: non-protected frames take a plain
--  SetScale, protected frames are scaled inside the SecureHandler snippet so
--  the write cannot taint by construction. Position offsets are stored in
--  frame-local units, so on a scale change the active offsets are multiplied
--  by oldScale/newScale and re-applied -- the frame stays visually put.
-------------------------------------------------------------------------------
local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.5, 2, 0.1

local function SecureSetScale(widget, scale)
    if InCombatLockdown() then
        return false
    end
    positioner:SetFrameRef("f", widget)
    positioner:SetAttribute("s", scale)
    positioner:Execute([[
        local f = self:GetFrameRef("f")
        if f then f:SetScale(self:GetAttribute("s")) end
    ]])
    return true
end

local function SetShifterScale(widget, scale)
    -- Guard the SetScale reentry hook (below) so our own re-scale never
    -- recurses -- mirrors the _shIgnoreSP guard used for SetPoint.
    local frameData = GetFFD(widget)
    frameData._shIgnoreSS = true
    local success
    if Secured(widget) then
        success = SecureSetScale(widget, scale)
    else
        widget:SetScale(scale)
        success = true
    end
    frameData._shIgnoreSS = false
    return success
end

-- OnShow / init restore: temp > saved > (original, if we scaled it earlier).
local function ApplyScale(widget, frameName)
    if InCombatLockdown() and Secured(widget) then
        return
    end
    local frameData = GetFFD(widget)
    local target = tempScale[widget] or GetSavedScale(frameName)
    if target then
        if frameData._shOrigScale == nil then
            frameData._shOrigScale = widget:GetScale()
        end
        frameData._shScaled = true
    else
        if not (frameData._shScaled and frameData._shOrigScale) then
            return
        end
        target = frameData._shOrigScale
        frameData._shScaled = nil
    end
    if math.abs(widget:GetScale() - target) < 0.001 then
        return
    end
    SetShifterScale(widget, target)
end

local function ApplyScaleStep(widget, frameName, delta, modeName)
    if InCombatLockdown() and Secured(widget) then
        return
    end
    local frameData = GetFFD(widget)
    if frameData._shOrigScale == nil then
        frameData._shOrigScale = widget:GetScale()
    end
    local oldS = widget:GetScale()
    local current = tempScale[widget] or GetSavedScale(frameName) or oldS
    local new = math.floor((current + SCALE_STEP * delta) * 100 + 0.5) / 100
    if new < SCALE_MIN then
        new = SCALE_MIN
    elseif new > SCALE_MAX then
        new = SCALE_MAX
    end
    if new == current and math.abs(oldS - new) < 0.005 then
        return
    end
    if not SetShifterScale(widget, new) then
        return
    end
    frameData._shScaled = true

    -- Keep the frame visually in place: rescale whichever position table is
    -- (or becomes) active, then re-apply it.
    local ratio = oldS / new
    -- With NO stored position, Blizzard's panel manager re-seats the scaled window on
    -- its next layout pass (first tab switch) and it visibly jumps. Zooming therefore
    -- claims the seat like dragging does: capture the current visual spot
    -- (center-based, frame-local units at the NEW scale) so the pin holds it.
    local function CaptureCenter()
        local fcx, fcy = widget:GetCenter()
        local uiCursorX, uiCursorY = UIParent:GetCenter()
        if not fcx or not uiCursorX then
            return nil
        end
        local effScale = widget:GetEffectiveScale()
        local uiScale = UIParent:GetEffectiveScale()
        return (fcx * effScale - uiCursorX * uiScale) / effScale, (fcy * effScale - uiCursorY * uiScale) / effScale
    end
    if modeName == "save" then
        SaveScale(frameName, new)
        tempScale[widget] = nil
        local stored = GetSavedPos(frameName)
        if stored then
            SavePos(frameName, stored.point, stored.relPoint, stored.x * ratio, stored.y * ratio)
        elseif not tempPos[widget] then
            local cursorX, cursorY = CaptureCenter()
            if cursorX then
                SavePos(frameName, "CENTER", "CENTER", cursorX, cursorY)
            end
        end
        if tempPos[widget] then
            tempPos[widget].x = tempPos[widget].x * ratio
            tempPos[widget].y = tempPos[widget].y * ratio
        end
    else
        tempScale[widget] = new
        if tempPos[widget] then
            tempPos[widget].x = tempPos[widget].x * ratio
            tempPos[widget].y = tempPos[widget].y * ratio
        else
            local stored = GetSavedPos(frameName)
            if stored then
                tempPos[widget] = {
                    point = stored.point,
                    relPoint = stored.relPoint,
                    x = stored.x * ratio,
                    y = stored.y * ratio,
                }
            else
                local cursorX, cursorY = CaptureCenter()
                if cursorX then
                    tempPos[widget] = {
                        point = "CENTER",
                        relPoint = "CENTER",
                        x = cursorX,
                        y = cursorY,
                    }
                end
            end
        end
    end
    ApplyPosition(widget, frameName)
end

-------------------------------------------------------------------------------
--  Scroll-wheel capture overlay
--
--  No Blizzard frame ever gets EnableMouseWheel (input-state writes are the
--  exact call class that tainted PVEFrame). Instead one overlay frame of our
--  own sits over the hovered registered panel while Shift/Ctrl is held and
--  takes the wheel. EnableMouse stays false so clicks (and the existing
--  drag hooks) pass straight through; with no modifier held it is hidden and
--  costs nothing.
-------------------------------------------------------------------------------
local wheelTarget, wheelTargetName
local wheelCatcher = CreateFrame("Frame", nil, UIParent)
wheelCatcher:Hide()
wheelCatcher:EnableMouse(false)
wheelCatcher:EnableMouseWheel(true)
wheelCatcher:SetFrameStrata("TOOLTIP")

-- True zero cost while no registered panel is open: the wheel machinery is
-- armed by panel VISIBILITY. WheelArm.shown counts visible registry frames
-- (OnShow/OnHide hooks installed in HookFrame); the 0<->1 edges register and
-- unregister MODIFIER_STATE_CHANGED itself, so with every panel closed a
-- modifier press never enters Lua and the overlay (with its 10Hz poll) stays
-- hidden. The drag path needs none of this -- its hooks are click-driven.
-- One table = one file-scope local; Sync/Note defined below UpdateWheelOverlay.
local WheelArm = { shown = 0 }

local function FindWheelTarget()
    for index = 1, #hookedFrames do
        local e = hookedFrames[index]
        if e.frame:IsVisible() and e.frame:IsMouseOver() then
            return e.frame, e.name
        end
    end
end

local function UpdateWheelOverlay()
    if WheelArm.shown == 0 or not (IsEnabled() and (IsShiftKeyDown() or IsControlKeyDown())) then
        wheelTarget, wheelTargetName = nil, nil
        wheelCatcher:Hide()
        return
    end
    local frame, frameName = FindWheelTarget()
    wheelTarget, wheelTargetName = frame, frameName
    wheelCatcher:ClearAllPoints()
    if frame then
        wheelCatcher:SetAllPoints(frame)
        wheelCatcher:EnableMouseWheel(true)
    else
        -- Parked but shown: the OnUpdate keeps polling so hovering onto a
        -- panel AFTER pressing the modifier still arms the wheel.
        wheelCatcher:SetSize(1, 1)
        wheelCatcher:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -20, -20)
        wheelCatcher:EnableMouseWheel(false)
    end
    wheelCatcher:Show()
end

do
    local acc = 0
    wheelCatcher:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 0.1 then
            return
        end
        acc = 0
        UpdateWheelOverlay()
    end)
end

wheelCatcher:SetScript("OnMouseWheel", function(_, delta)
    local widget, frameName = wheelTarget, wheelTargetName
    if not widget or not IsEnabled() then
        return
    end
    if IsShiftKeyDown() then
        ApplyScaleStep(widget, frameName, delta, "save")
    elseif IsControlKeyDown() then
        ApplyScaleStep(widget, frameName, delta, "temp")
    end
end)

-- Arm/disarm the modifier listener from the visible-panel count. IsEnabled is
-- re-read here, so count edges while the feature is toggled off keep the
-- listener down, and the mid-session enable path (InitShifter tail) re-arms
-- even with a panel already open. UpdateWheelOverlay runs on both edges: on
-- arm a modifier may already be held as the panel opens; on disarm its head
-- gate parks the overlay.
function WheelArm.Sync()
    if not watcher then
        return
    end
    if WheelArm.shown > 0 and IsEnabled() then
        watcher:RegisterEvent("MODIFIER_STATE_CHANGED")
    else
        watcher:UnregisterEvent("MODIFIER_STATE_CHANGED")
    end
    UpdateWheelOverlay()
end

function WheelArm.Note(delta)
    local was = WheelArm.shown
    local nowTime = was + delta
    if nowTime < 0 then
        nowTime = 0
    end
    WheelArm.shown = nowTime
    if (was == 0) ~= (nowTime == 0) then
        WheelArm.Sync()
    end
end

-------------------------------------------------------------------------------
--  Cursor-delta drag (for PROTECTED frames)
--
--  We can't StartMoving a protected frame without tainting it, so for those we
--  track the cursor ourselves and reposition the frame live via SecureSetPoint
--  each update. Position is stored center-relative to UIParent (scale-clean).
--  Only one protected frame can be dragged at a time.
-------------------------------------------------------------------------------
local dragHandle = {} -- { frame, name, mode, cursorX, cursorY, startX, startY, curX, curY }
local dragUpdater = CreateFrame("Frame")
dragUpdater:Hide()

local function StopSecureDrag()
    dragUpdater:Hide()
    local widget = dragHandle.frame
    if not widget then
        return
    end
    if dragHandle.curX then
        if dragHandle.mode == "save" then
            SavePos(dragHandle.name, "CENTER", "CENTER", dragHandle.curX, dragHandle.curY)
            tempPos[widget] = nil
        else
            tempPos[widget] =
                { point = "CENTER", relPoint = "CENTER", x = dragHandle.curX, y = dragHandle.curY }
        end
    end
    dragHandle.frame = nil
end

dragUpdater:SetScript("OnUpdate", function()
    local widget = dragHandle.frame
    if not widget then
        dragUpdater:Hide()
        return
    end
    if InCombatLockdown() then
        StopSecureDrag()
        return
    end
    local cursorX, cursorY = GetCursorPosition()
    local effScale = widget:GetEffectiveScale()
    local uiScale = UIParent:GetEffectiveScale()
    local uiCursorX, uiCursorY = UIParent:GetCenter()
    local newScreenX = dragHandle.startX + (cursorX - dragHandle.cursorX)
    local newScreenY = dragHandle.startY + (cursorY - dragHandle.cursorY)
    -- Keep the frame's center on screen (protected frames skip SetClampedToScreen).
    local sw, sh = GetScreenWidth() * uiScale, GetScreenHeight() * uiScale
    if newScreenX < 0 then
        newScreenX = 0
    elseif newScreenX > sw then
        newScreenX = sw
    end
    if newScreenY < 0 then
        newScreenY = 0
    elseif newScreenY > sh then
        newScreenY = sh
    end
    local posX = (newScreenX - uiCursorX * uiScale) / effScale
    local posY = (newScreenY - uiCursorY * uiScale) / effScale
    dragHandle.curX, dragHandle.curY = posX, posY
    local frameData = GetFFD(widget)
    frameData._shIgnoreSP = true
    SecureSetPoint(widget, "CENTER", "CENTER", posX, posY)
    frameData._shIgnoreSP = false
end)

local function StartSecureDrag(widget, frameName, modeName)
    local fcx, fcy = widget:GetCenter()
    if not fcx then
        return
    end
    local effScale = widget:GetEffectiveScale()
    dragHandle.frame = widget
    dragHandle.name = frameName
    dragHandle.mode = modeName
    dragHandle.cursorX, dragHandle.cursorY = GetCursorPosition()
    dragHandle.startX, dragHandle.startY = fcx * effScale, fcy * effScale
    dragHandle.curX, dragHandle.curY = nil, nil
    dragUpdater:Show()
end

-------------------------------------------------------------------------------
--  Companion re-dock on CharacterFrame changes.
--
--  Each DOCKING_COMPANIONS frame only re-evaluates its own docked position
--  when ITS OWN OnShow/SetPoint fires -- never when CharacterFrame itself
--  moves or rescales. So a companion (WorldMap, Guild/Communities, PVEFrame,
--  etc.) that's already open and correctly docked goes stale the moment
--  CharacterFrame is scaled or repositioned afterward, since nothing tells
--  it to re-check. Every companion registers its ShouldDock/DockToCharacter-
--  Frame closures here as it's hooked; CharacterFrame's own SetPoint/SetScale
--  (hooked separately below) walks this list and re-docks anything that
--  should currently be docked, closing that gap.
-------------------------------------------------------------------------------
local dockedCompanions = {}

local function RedockCompanions()
    for index = 1, #dockedCompanions do
        local c = dockedCompanions[index]
        if c.frame:IsShown() and c.shouldDock() then
            if c.liftStrata and not Secured(c.frame) then
                c.frame:SetFrameStrata("DIALOG")
            end
            c.dock()
            if not Secured(c.frame) then
                c.frame:Raise()
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Hook a single frame
-------------------------------------------------------------------------------
local function HookFrame(widget, frameName)
    local frameData = GetFFD(widget)
    if frameData._shHooked then
        return
    end
    frameData._shHooked = true
    hookedFrames[#hookedFrames + 1] = { frame = widget, name = frameName }

    if SECURE_PATH[frameName] then
        frameData._shSecure = true
    end
    -- Lifted over a moved CharacterFrame by strata and Raise, or by Raise alone (NO_STRATA_LIFT).
    local liftStrata = not NO_STRATA_LIFT[frameName]

    -- Wheel arming rides panel visibility (WheelArm.Note): registry frames
    -- are all top-level closable panels, so OnShow/OnHide track exactly the
    -- IsVisible state FindWheelTarget tests. A frame hooked while already
    -- open (LoD addon load, /reload with the map up) counts immediately.
    widget:HookScript("OnShow", function()
        WheelArm.Note(1)
    end)
    widget:HookScript("OnHide", function()
        WheelArm.Note(-1)
    end)
    if widget:IsShown() then
        WheelArm.Note(1)
    end

    -- Non-protected frames use the cheap native StartMoving path. Protected frames
    -- (and SECURE_PATH windows) are NEVER made movable / SetMovable'd / StartMoving'd /
    -- SetPoint'd by insecure code (it taints them); they drag via the secure
    -- cursor-delta path above. SetMovable is only needed for StartMoving, so they
    -- skip it entirely.
    if not Secured(widget) then
        widget:SetMovable(true)
        widget:SetClampedToScreen(true)
    end

    local dragging -- non-protected only: "save" | "temp" | nil

    local function AttachDrag(dragTarget)
        if not dragTarget or not dragTarget.HookScript then
            return
        end
        dragTarget:HookScript("OnMouseDown", function(_, btnFrame)
            if not IsEnabled() then
                return
            end
            if btnFrame ~= "LeftButton" then
                return
            end
            if InCombatLockdown() and Secured(widget) then
                return
            end
            local noShift = CludesUIDB and CludesUIDB.shifterNoShift
            local modeName
            if IsShiftKeyDown() or noShift then
                modeName = "save"
            elseif IsControlKeyDown() then
                modeName = "temp"
            else
                return
            end
            if Secured(widget) then
                StartSecureDrag(widget, frameName, modeName)
            else
                dragging = modeName
                widget:StartMoving()
            end
        end)

        dragTarget:HookScript("OnMouseUp", function(_, btnFrame)
            if btnFrame ~= "LeftButton" then
                return
            end
            if Secured(widget) then
                if dragHandle.frame == widget then
                    StopSecureDrag()
                end
                return
            end
            if not dragging then
                return
            end
            widget:StopMovingOrSizing()
            widget:SetUserPlaced(false)
            local p, _, rp, posX, posY = widget:GetPoint(1)
            if p then
                if dragging == "save" then
                    SavePos(frameName, p, rp, posX, posY)
                    tempPos[widget] = nil
                else
                    tempPos[widget] = {
                        point = p,
                        relPoint = rp,
                        x = posX,
                        y = posY,
                    }
                end
            end
            -- A drag ends with no SetPoint call, and a secured companion docks
            -- by an absolute position: dock the open ones beside it again.
            if frameName == "CharacterFrame" then
                RedockCompanions()
            end
            dragging = nil
        end)
    end

    -- Primary drag target (header child or the frame itself)
    local headerName = DRAG_HEADERS[frameName]
    AttachDrag((headerName and _G[headerName]) or widget)

    -- Extra handles layered on top of the frame body
    local extra = EXTRA_DRAG_TARGETS[frameName]
    if type(extra) == "table" then
        for _, childFrame in ipairs(extra) do
            AttachDrag(_G[childFrame])
        end
    elseif extra then
        AttachDrag(type(extra) == "function" and extra(widget) or _G[extra])
    end

    widget:HookScript("OnShow", function()
        if not IsEnabled() then
            return
        end
        -- Scale first: stored position offsets are frame-local units, so the
        -- pin only lands right once the final scale is in effect.
        ApplyScale(widget, frameName)
        ApplyPosition(widget, frameName)
    end)

    widget:HookScript("OnHide", function()
        if not IsEnabled() then
            return
        end
        if dragHandle.frame == widget then
            StopSecureDrag()
        end
        tempPos[widget] = nil
        tempScale[widget] = nil
    end)

    -- Item Upgrade / Transmog / Item Socketing / Merchant (covers vendors like the
    -- Crest Exchange) dock beside CharacterFrame. Blizzard's own docking math assumes
    -- CharacterFrame sits at its default screen position; once Shifter has
    -- CharacterFrame pinned somewhere else that math falls apart and the companion
    -- ends up wherever Blizzard's now- wrong calculation put it -- frequently right on
    -- top of CharacterFrame's pinned spot, and since CharacterFrame's skin forces it
    -- to "HIGH" strata while these default to "MEDIUM", it then renders buried
    -- underneath. Docks left by default (matching Blizzard's normal layout), falling
    -- back to whichever side actually has room -- otherwise SetClampedToScreen just
    -- snaps it back onto CharacterFrame regardless of which side we pick. A companion
    -- with its own pin keeps it unless that spot would overlap the moved CharacterFrame
    -- (whichever window moved last); then it docks beside it instead.
    local ShouldDock, DockToCharacterFrame
    if DOCKING_COMPANIONS[frameName] then
        local defaultStrata = widget:GetFrameStrata()
        ShouldDock = function()
            -- Protected frames (PVEFrame) still dock -- but position-only,
            -- through the SecureSetPoint branch below; their strata/Raise
            -- touches are skipped in the OnShow/OnHide hooks (insecure writes
            -- taint a protected tree -- the PVEFrame SetMovable incident).
            local castFrame = _G.CharacterFrame
            if
                not (
                    castFrame
                    and castFrame:IsShown()
                    and (tempPos[castFrame] or GetSavedPos("CharacterFrame"))
                )
            then
                return false
            end
            local own = tempPos[widget] or GetSavedPos(frameName)
            return not own or SavedPosOverlaps(widget, own, castFrame)
        end
        DockToCharacterFrame = function()
            local castFrame = _G.CharacterFrame
            local margin = 4
            -- Compare available room in SCREEN-ABSOLUTE units. cf's edges are in CF's
            -- effective-scale space and this frame's width is in its own; raw mixing
            -- picks the wrong side (and mis-places the protected dock below) the moment
            -- either frame is Shifter-scaled -- which is the headline scenario here.
            local cs = castFrame:GetEffectiveScale() or 1
            local effScale = widget:GetEffectiveScale() or 1
            local uiScale = UIParent:GetEffectiveScale() or 1
            local wAbs = (widget:GetWidth() or 0) * effScale
            local leftRoom = (castFrame:GetLeft() or 0) * cs
            local rightRoom = (GetScreenWidth() or 0) * uiScale - (castFrame:GetRight() or 0) * cs
            local dockLeft = leftRoom >= wAbs + margin * effScale or leftRoom >= rightRoom
            if Secured(widget) then
                -- Plain SetPoint on a protected frame (e.g. PVEFrame) taints it -- same
                -- reason SecureSetPoint exists for saved/dragged positions above.
                -- SecureSetPoint only anchors relative to UIParent, so convert the dock
                -- target into a UIParent-CENTER offset, with every coordinate
                -- normalized through its own frame's effective scale (screen-absolute
                -- space) before dividing back into this frame's units.
                if InCombatLockdown() then
                    return
                end
                local hAbs = (widget:GetHeight() or 0) * effScale
                local absCenterX
                if dockLeft then
                    absCenterX = leftRoom - margin * effScale - wAbs / 2
                else
                    absCenterX = (castFrame:GetRight() or 0) * cs + margin * effScale + wAbs / 2
                end
                local absCenterY = (castFrame:GetTop() or 0) * cs - hAbs / 2
                local uiCursorX, uiCursorY = UIParent:GetCenter()
                if uiCursorX and effScale > 0 then
                    SecureSetPoint(
                        widget,
                        "CENTER",
                        "CENTER",
                        (absCenterX - uiCursorX * uiScale) / effScale,
                        (absCenterY - uiCursorY * uiScale) / effScale
                    )
                end
            else
                frameData._shIgnoreSP = true
                widget:ClearAllPoints()
                if dockLeft then
                    widget:SetPoint("TOPRIGHT", castFrame, "TOPLEFT", -margin, 0)
                else
                    widget:SetPoint("TOPLEFT", castFrame, "TOPRIGHT", margin, 0)
                end
                frameData._shIgnoreSP = false
            end
        end
        widget:HookScript("OnHide", function()
            -- Strata writes are INSECURE: on a protected frame (PVEFrame)
            -- they taint its whole tree, exactly like the SetMovable call
            -- that caused the original secret-value incident. Skip them.
            if liftStrata and not Secured(widget) then
                widget:SetFrameStrata(defaultStrata)
            end
        end)
        widget:HookScript("OnShow", function()
            if not IsEnabled() then
                return
            end
            if ShouldDock() then
                -- The strata raise only matters when the companion OVERLAPS
                -- CharacterFrame -- a docked frame no longer does. Protected
                -- frames therefore get position-only docking; strata and
                -- Raise are insecure writes that would taint their tree.
                if liftStrata and not Secured(widget) then
                    widget:SetFrameStrata("DIALOG")
                end
                DockToCharacterFrame()
                if not Secured(widget) then
                    widget:Raise()
                end
            end
        end)
        dockedCompanions[#dockedCompanions + 1] = {
            frame = widget,
            shouldDock = ShouldDock,
            dock = DockToCharacterFrame,
            liftStrata = liftStrata,
        }
    elseif frameName == "CharacterFrame" then
        -- CharacterFrame itself isn't a companion, but every companion's dock
        -- is relative to IT -- so a scale or position change here is exactly
        -- what leaves already-open companions stale (see RedockCompanions).
        hooksecurefunc(widget, "SetPoint", function()
            if IsEnabled() then
                RedockCompanions()
            end
        end)
        hooksecurefunc(widget, "SetScale", function()
            if IsEnabled() then
                RedockCompanions()
            end
        end)
    else
        -- Any other Shifter-managed window can end up rendered underneath a
        -- Shifter-pinned CharacterFrame purely because CharacterFrame's skin forces it
        -- to "HIGH" strata -- not because it's meant to dock beside CharacterFrame
        -- (unlike DOCKING_COMPANIONS, this never touches position, just strata).
        -- Applies generically to every other Shifter-hooked frame so newly discovered
        -- cases don't need a hardcoded entry. Protected frames are skipped:
        -- SetFrameStrata and Raise are still INSECURE writes, and on a protected frame
        -- they taint its whole tree (the PVEFrame SetMovable incident) -- those stay at
        -- Blizzard strata, possibly buried but never tainted.
        local defaultStrata = widget:GetFrameStrata()
        widget:HookScript("OnHide", function()
            if liftStrata and not Secured(widget) then
                widget:SetFrameStrata(defaultStrata)
            end
        end)
        widget:HookScript("OnShow", function()
            if not IsEnabled() then
                return
            end
            if Secured(widget) then
                return
            end
            local castFrame = _G.CharacterFrame
            if
                castFrame
                and castFrame:IsShown()
                and (tempPos[castFrame] or GetSavedPos("CharacterFrame"))
            then
                if liftStrata then
                    widget:SetFrameStrata("DIALOG")
                end
                widget:Raise()
            end
        end)
    end

    hooksecurefunc(widget, "SetPoint", function()
        if not IsEnabled() then
            return
        end
        if frameData._shIgnoreSP then
            return
        end
        if dragHandle.frame == widget then
            return
        end -- don't fight an active drag
        if InCombatLockdown() and Secured(widget) then
            return
        end
        if DockToCharacterFrame and ShouldDock() then
            DockToCharacterFrame()
            return
        end
        if tempPos[widget] or GetSavedPos(frameName) then
            ApplyPosition(widget, frameName)
        end
    end)

    -- Re-assert the user's scale whenever Blizzard (or anything) changes it in place.
    -- Some windows rescale themselves on a state change with no hide/show to fire the
    -- OnShow restore -- e.g. the crafting order window resets its scale when you submit
    -- an order, so a scaled window snapped back. Only re-assert for frames the user has
    -- actually scaled; guarded so our own re-scale can't recurse.
    hooksecurefunc(widget, "SetScale", function()
        if not IsEnabled() then
            return
        end
        if frameData._shIgnoreSS then
            return
        end
        if InCombatLockdown() and Secured(widget) then
            return
        end
        if tempScale[widget] or GetSavedScale(frameName) then
            ApplyScale(widget, frameName)
        end
    end)

    -- If the frame is already visible, apply saved scale + position now
    if widget:IsVisible() then
        ApplyScale(widget, frameName)
        ApplyPosition(widget, frameName)
    end
end

local function TryHook(frameName)
    -- WoW Forever's Gamepad interface style: no panel hooks (see InitShifter).
    if CludesUI.PadGamepadUI() then
        return
    end
    local widget = _G[frameName]
    if widget and widget.HookScript then
        HookFrame(widget, frameName)
    end
end

-- Windows of our own modules that are built after login (Forever Essentials'
-- classic spellbook and talent window): each module hands its window over by
-- name as it builds it, and an enable later in the session hooks the ones
-- already handed over. Placed at once, since such a window can first open in
-- combat, when a protected one cannot be moved.
local adopted = {}

local function HookAdopted(frameName)
    if CludesUI.PadGamepadUI() then
        return
    end
    local widget = _G[frameName]
    if not (widget and widget.HookScript) then
        return
    end
    HookFrame(widget, frameName)
    if not InCombatLockdown() then
        ApplyScale(widget, frameName)
        ApplyPosition(widget, frameName)
    end
end

function CludesUI._ShifterAdopt(frameName)
    if adopted[frameName] then
        return
    end
    adopted[frameName] = true
    if IsEnabled() then
        HookAdopted(frameName)
    end
end

-------------------------------------------------------------------------------
--  Loot windows via Unlock Mode movers
--
--  The Bonus Roll window and the group loot roll container cannot be made
--  drag-movable: their top-level frames take no mouse input, and Blizzard
--  re-anchors them through SetPoint on every show and re-layout
--  (GroupLootContainer_Update anchors each roll frame, the bottom managed
--  column's Layout anchors the container). Instead each gets a mover in
--  Unlock Mode. The mover drags a proxy frame we own; the saved position
--  reaches the Blizzard window through the shared frame placer
--  (CludesUI.SetFramePlacer), which puts it back after every Blizzard
--  SetPoint (the container as the column's layout returns, before it is
--  drawn) and writes nothing on the Blizzard frame. No script hook either:
--  the windows show inside
--  GroupLootContainer_Update, and code run from their OnShow would leave the
--  rest of that update, the managed column layout, under our taint.
--  Protected or forbidden frames are skipped entirely, and no mouse state is
--  ever touched. A window is claimed only while the feature is on and it has
--  a saved position.
--
--  AlertFrame is the anchor every toast banner stacks up from (loot and
--  currency toasts, achievements, gold, recipes, Trading Post activities).
--  Blizzard anchors it once in XML and never again, so the placement made
--  when it is claimed is what moves it. Its own rect is a bare anchor rather
--  than a toast-sized box, so its mover uses a fixed size (fixedSize).
--
--  The capture bars ride the same recipe under the battleground switch and
--  overlay toggle they share with the flag carriers below (switch, hideKey):
--  UIWidgetBelowMinimapContainerFrame, the
--  first frame of the right managed column, holds the bars Blizzard shows
--  under the minimap (battleground capture bars, other objective bars). The
--  column grows as bars come and go, so it hangs from its mover's top edge
--  (anchor), with a fixed mover box to measure from.
-------------------------------------------------------------------------------
local LOOT_WINDOWS = {
    {
        name = "BonusRollFrame",
        key = "CUI_BonusRoll",
        label = "Bonus Roll",
        order = 640,
        defW = 330,
        defH = 120,
        defY = 240,
    },
    {
        name = "GroupLootContainer",
        key = "CUI_GroupLoot",
        label = "Group Loot",
        order = 641,
        defW = 300,
        defH = 80,
        defY = 340,
    },
    {
        name = "AlertFrame",
        key = "CUI_AlertToasts",
        label = "Alert Toasts",
        order = 642,
        defW = 300,
        defH = 100,
        defY = 160,
        fixedSize = true,
    },
    {
        name = "UIWidgetBelowMinimapContainerFrame",
        key = "CUI_CaptureBars",
        label = "Capture Bars",
        order = 644,
        defW = 230,
        defH = 60,
        defPos = { "TOPRIGHT", "TOPRIGHT", -20, -260 },
        fixedSize = true,
        anchor = "TOP",
        switch = "shifterBattlegroundUnlock",
        hideKey = "shifterBattlegroundHideOverlays",
        subtitle = "Disable the Battleground Frames overlays in Shifter once done positioning",
    },
}

local lootProxies = {}
local lootPlacers = {} -- name -> placement callback, built once per window
local lootTaken = {} -- name -> true while our placement claim is registered

local function LootEnabled(details)
    local store = CludesUIDB
    return store and store[details.switch or "shifterLootUnlock"] or false
end

local function GetLootPos(frameName)
    local store = CludesUIDB
    return store and store.shifterLootPositions and store.shifterLootPositions[frameName]
end

local function SaveLootPos(frameName, anchorPoint, relPoint, posX, posY)
    if not CludesUIDB then
        CludesUIDB = {}
    end
    if not CludesUIDB.shifterLootPositions then
        CludesUIDB.shifterLootPositions = {}
    end
    CludesUIDB.shifterLootPositions[frameName] = {
        point = anchorPoint,
        relPoint = relPoint,
        x = posX,
        y = posY,
    }
end

-- The live Blizzard frame, once loaded. The placer refuses protected,
-- forbidden and anchor-restricted frames itself (secret-safe), so such a
-- window is never claimed.
local function LootFrame(frameName)
    local widget = _G[frameName]
    if type(widget) == "table" then
        return widget
    end
end

-- The saved spot while the feature is on; nil leaves the window to the next
-- placement owner, or to Blizzard's own anchor.
local function LootPlacer(details)
    local frameName = details.name
    local func = lootPlacers[frameName]
    if not func then
        func = function()
            if not LootEnabled(details) then
                return nil
            end
            local place = GetLootPos(frameName)
            if not place then
                return nil
            end
            local anchor = details.anchor
            if anchor then
                local dx, dy = AnchorShift(place.point, anchor, details.defW, details.defH)
                return anchor, UIParent, place.relPoint, place.x + dx, place.y + dy
            end
            return place.point, UIParent, place.relPoint, place.x, place.y
        end
        lootPlacers[frameName] = func
    end
    return func
end

-- Drops our claim: the placer hands the window to the next owner, or back to
-- Blizzard's last anchor.
local function ReleaseLootWindow(frameName)
    if not lootTaken[frameName] then
        return
    end
    lootTaken[frameName] = nil
    local widget = LootFrame(frameName)
    if widget then
        CludesUI.SetFramePlacer(widget, "shifter", nil)
    end
end

-- Claims the window while the feature is on and a position is saved, and
-- places it this frame; releases it otherwise.
local function SyncLootWindow(details)
    local frameName = details.name
    if not (LootEnabled(details) and GetLootPos(frameName)) then
        ReleaseLootWindow(frameName)
        return
    end
    local widget = LootFrame(frameName)
    if not widget then
        return
    end
    if not lootTaken[frameName] then
        if not CludesUI.SetFramePlacer(widget, "shifter", LootPlacer(details)) then
            return
        end
        lootTaken[frameName] = true
    end
    CludesUI.RequestFramePlacement(widget)
end

-- The proxy sits at the saved position, or at the window's default spot.
local function PlaceLootProxy(proxyFrame, details)
    local place = GetLootPos(details.name)
    proxyFrame:ClearAllPoints()
    if place then
        proxyFrame:SetPoint(place.point, UIParent, place.relPoint, place.x, place.y)
    elseif details.defPos then
        local skinData = details.defPos
        proxyFrame:SetPoint(skinData[1], UIParent, skinData[2], skinData[3], skinData[4])
    else
        proxyFrame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, details.defY)
    end
end

-- Hidden rect-only ghost the unlock mover attaches to; never visible.
local function EnsureLootProxy(details)
    local proxyFrame = lootProxies[details.name]
    if proxyFrame then
        return proxyFrame
    end
    proxyFrame = CreateFrame("Frame", nil, UIParent)
    proxyFrame:Hide()
    proxyFrame:SetSize(details.defW, details.defH)
    PlaceLootProxy(proxyFrame, details)
    lootProxies[details.name] = proxyFrame
    return proxyFrame
end

-- Each window by its own switch: claimed while it is on with a saved spot,
-- released otherwise.
local function InitLootWindows()
    for index = 1, #LOOT_WINDOWS do
        SyncLootWindow(LOOT_WINDOWS[index])
    end
end

local function RegisterLootUnlockElements()
    local MK = CludesUI.MakeUnlockElement
    if not MK or not CludesUI.RegisterUnlockElements then
        return
    end
    local elements = {}
    for index = 1, #LOOT_WINDOWS do
        local details = LOOT_WINDOWS[index]
        elements[#elements + 1] = MK({
            key = details.key,
            label = details.label,
            group = "Utilities",
            order = details.order,
            noResize = true,
            noAnchorTarget = true,
            noAnchorTo = true,
            noSizeMatchTarget = true,
            -- Loot movers position hidden proxies, so their overlays linger
            -- until the user turns them off: brown tint + reminder subtitle
            -- to tell them apart from live-frame movers.
            moverBg = { r = 0.165, g = 0.11, b = 0.055 },
            subtitle = details.subtitle
                or "Disable Loot layout mode overlays in Shifter once done positioning",
            isHidden = function()
                if not LootEnabled(details) or not _G[details.name] then
                    return true
                end
                -- "Hide Unlock Mode Overlays": the movers stay out of unlock
                -- mode but saved positions keep applying (the placer claim
                -- never depends on the movers existing).
                return CludesUIDB and CludesUIDB[details.hideKey or "shifterLootHideOverlays"] or false
            end,
            getFrame = function()
                return EnsureLootProxy(details)
            end,
            getSize = function()
                if details.fixedSize then
                    return details.defW, details.defH
                end
                local widget = _G[details.name]
                local wid = widget and widget.GetWidth and widget:GetWidth() or 0
                local hgt = widget and widget.GetHeight and widget:GetHeight() or 0
                if not wid or wid < 20 then
                    wid = details.defW
                end
                if not hgt or hgt < 20 then
                    hgt = details.defH
                end
                return wid, hgt
            end,
            savePos = function(_, anchorPoint, relPoint, posX, posY)
                SaveLootPos(details.name, anchorPoint, relPoint, posX, posY)
                PlaceLootProxy(EnsureLootProxy(details), details)
                SyncLootWindow(details)
            end,
            loadPos = function()
                local place = GetLootPos(details.name)
                if place then
                    return { point = place.point, relPoint = place.relPoint, x = place.x, y = place.y }
                end
                return nil
            end,
            clearPos = function()
                if CludesUIDB and CludesUIDB.shifterLootPositions then
                    CludesUIDB.shifterLootPositions[details.name] = nil
                end
                local proxyFrame = lootProxies[details.name]
                if proxyFrame then
                    PlaceLootProxy(proxyFrame, details)
                end
                ReleaseLootWindow(details.name)
            end,
            applyPos = function()
                PlaceLootProxy(EnsureLootProxy(details), details)
                SyncLootWindow(details)
            end,
        })
    end
    CludesUI:RegisterUnlockElements(elements, "CludesUIQoL")
end

-------------------------------------------------------------------------------
--  Blizzard Top Bar Event Text (UIWidgetTopCenterContainerFrame) via an
--  Unlock Mode mover -- the loot-window recipe (hidden proxy + mover, no
--  script hook, no mouse state ever touched) with ONE substitution: every
--  position write on the live frame runs through SecureSetPoint, never the
--  shared frame placer. The container hosts encounter and scenario
--  status-bar widgets whose Blizzard code compares SECRET values in
--  instanced combat; an insecure ClearAllPoints/SetPoint would taint that
--  tree and throw "attempt to compare a secret number" (see Secure
--  repositioning above). The plain SetPoint writes the loot windows take are
--  safe only because their subtrees never touch secrets.
--
--  Blizzard anchors the container once in XML (TOP of UIParent, 0, -15, on
--  both clients) and never again in normal play, and it keeps that anchor
--  through hide and show. So the saved spot is written once, shown or not,
--  and again only when something else calls the container's SetPoint (a
--  secure post-hook; the restricted environment's SetPoint never reaches
--  it). SecureSetPoint bails in combat: a missed write waits for the
--  module's combat queue, which decides again what to write.
-------------------------------------------------------------------------------
local TOPBAR_NAME = "UIWidgetTopCenterContainerFrame"
local TOPBAR_KEY, TOPBAR_LABEL = "CUI_TopBarEventText", "Top Bar Event Text"
local TOPBAR_DEFW, TOPBAR_DEFH, TOPBAR_DEFY = 400, 60, -120
local TOPBAR_HOMEY = -15 -- Blizzard's own anchor: TOP of UIParent at this y

local topProxy
local topBarHooked = false
local topBarMoved = false -- our anchor is on the container
local topBarWriting = false -- our own secure write is running

local function TopBarEnabled()
    return CludesUIDB and CludesUIDB.shifterTopBarUnlock or false
end

local function GetTopBarPos()
    return CludesUIDB and CludesUIDB.shifterTopBarPos
end

local function SaveTopBarPos(anchorPoint, relPoint, posX, posY)
    if not CludesUIDB then
        CludesUIDB = {}
    end
    CludesUIDB.shifterTopBarPos = { point = anchorPoint, relPoint = relPoint, x = posX, y = posY }
end

-- Returns the live Blizzard frame only when it is safe to reposition. A
-- secret answer (ObjectSecurity aspect) counts as unsafe.
local function TopBarFrame()
    local widget = _G[TOPBAR_NAME]
    if type(widget) ~= "table" or not widget.IsForbidden then
        return nil
    end
    local val = widget:IsForbidden()
    if issecretvalue(val) or val then
        return nil
    end
    val = widget:IsProtected()
    if issecretvalue(val) or val then
        return nil
    end
    return widget
end

-- Our saved spot while the feature is on; otherwise Blizzard's own anchor,
-- and only while ours is still on the container. SECURE writes only (see
-- block comment); false = in combat, so the queue decides again later.
local function SyncTopBar()
    local widget = TopBarFrame()
    if not widget then
        return
    end
    local place = TopBarEnabled() and GetTopBarPos()
    if not place and not topBarMoved then
        return
    end
    local success
    topBarWriting = true
    if place then
        success = SecureSetPoint(widget, place.point, place.relPoint, place.x, place.y)
    else
        success = SecureSetPoint(widget, "TOP", "TOP", 0, TOPBAR_HOMEY)
    end
    topBarWriting = false
    if success then
        topBarMoved = place and true or false
    else
        mod.CombatQueue.Defer("ShifterTopBar", SyncTopBar)
    end
end

local function HookTopBar()
    if topBarHooked then
        return
    end
    local widget = TopBarFrame()
    if not widget then
        return
    end
    topBarHooked = true
    -- Something else anchored the container: our spot goes back on while the
    -- feature is on; otherwise that anchor stands and ours is gone. The
    -- restricted environment's SetPoint is the C method, so our own write
    -- does not reach this hook; the guard stops a loop should it ever do so.
    hooksecurefunc(widget, "SetPoint", function()
        if topBarWriting then
            return
        end
        if TopBarEnabled() and GetTopBarPos() then
            SyncTopBar()
        else
            topBarMoved = false
        end
    end)
end

-- Hidden rect-only ghost the unlock mover attaches to; never visible.
local function EnsureTopBarProxy()
    if topProxy then
        return topProxy
    end
    topProxy = CreateFrame("Frame", nil, UIParent)
    topProxy:Hide()
    topProxy:SetSize(TOPBAR_DEFW, TOPBAR_DEFH)
    local place = GetTopBarPos()
    if place then
        topProxy:SetPoint(place.point, UIParent, place.relPoint, place.x, place.y)
    else
        topProxy:SetPoint("TOP", UIParent, "TOP", 0, TOPBAR_DEFY)
    end
    return topProxy
end

local function RegisterTopBarUnlockElement()
    local MK = CludesUI.MakeUnlockElement
    if not MK or not CludesUI.RegisterUnlockElements then
        return
    end
    CludesUI:RegisterUnlockElements({
        MK({
            key = TOPBAR_KEY,
            label = TOPBAR_LABEL,
            group = "Utilities",
            order = 643,
            noResize = true,
            noAnchorTarget = true,
            noAnchorTo = true,
            noSizeMatchTarget = true,
            moverBg = { r = 0.165, g = 0.11, b = 0.055 },
            subtitle = "Disable the Top Bar Event Text overlay in Shifter once done positioning",
            isHidden = function()
                if not TopBarEnabled() or not _G[TOPBAR_NAME] then
                    return true
                end
                -- "Hide Unlock Mode Overlay": mover stays out of unlock mode
                -- but the saved position keeps applying (the secure write and
                -- its SetPoint post-hook never depend on the mover existing).
                return CludesUIDB and CludesUIDB.shifterTopBarHideOverlay or false
            end,
            getFrame = EnsureTopBarProxy,
            -- Bare/dynamic rect (empty without widgets): fixed mover box.
            getSize = function()
                return TOPBAR_DEFW, TOPBAR_DEFH
            end,
            savePos = function(_, anchorPoint, relPoint, posX, posY)
                SaveTopBarPos(anchorPoint, relPoint, posX, posY)
                local proxyFrame = EnsureTopBarProxy()
                proxyFrame:ClearAllPoints()
                proxyFrame:SetPoint(anchorPoint, UIParent, relPoint, posX, posY)
                HookTopBar()
                SyncTopBar()
            end,
            loadPos = function()
                local place = GetTopBarPos()
                if place then
                    return { point = place.point, relPoint = place.relPoint, x = place.x, y = place.y }
                end
                return nil
            end,
            clearPos = function()
                if CludesUIDB then
                    CludesUIDB.shifterTopBarPos = nil
                end
                local proxyFrame = topProxy
                if proxyFrame then
                    proxyFrame:ClearAllPoints()
                    proxyFrame:SetPoint("TOP", UIParent, "TOP", 0, TOPBAR_DEFY)
                end
                SyncTopBar()
            end,
            applyPos = function()
                local place = GetTopBarPos()
                local proxyFrame = EnsureTopBarProxy()
                proxyFrame:ClearAllPoints()
                if place then
                    proxyFrame:SetPoint(place.point, UIParent, place.relPoint, place.x, place.y)
                else
                    proxyFrame:SetPoint("TOP", UIParent, "TOP", 0, TOPBAR_DEFY)
                end
                SyncTopBar()
            end,
        }),
    }, "CludesUIQoL")
end

-- Exposed for the options toggle (mid-session enable without /reload)
function CludesUI._InitShifterTopBar()
    HookTopBar()
    SyncTopBar()
end

-- Exposed for the options toggle, which turns the setting off first: the
-- container gets Blizzard's own anchor back (after combat if need be) and the
-- post-hook goes dormant through the TopBarEnabled gate.
function CludesUI._DisableShifterTopBar()
    SyncTopBar()
end

-------------------------------------------------------------------------------
--  Battleground flag carriers (ArenaEnemyMatchFramesContainer, the column of
--  Blizzard's carrier frames) via an Unlock Mode mover. The carriers are
--  SECURE unit buttons, so the column is protected and the frame placer
--  refuses it: every write on it runs through the restricted environment, out
--  of combat (one asked for in combat waits for the module's combat queue).
--  That is enough, because Blizzard anchors the column once in XML (TOPRIGHT
--  of its parent, -10, 0) and never again: the right managed column lays out
--  that parent, not the column. The parent keeps the column's height, so the
--  managed column still leaves the room the carriers took. The column hangs
--  from its mover's top-right corner, as from Blizzard's own anchor, so a
--  carrier who comes or goes never moves the others. Hidden proxy + mover, no
--  script hook, no mouse state ever touched.
-------------------------------------------------------------------------------
local CARRIER = {
    name = "ArenaEnemyMatchFramesContainer",
    w = 150,
    h = 160, -- the mover box, about four carriers
    defPos = { "TOPRIGHT", "TOPRIGHT", -40, -320 }, -- the mover before a first save
    moved = false, -- our anchor is on the column
}

-- The battleground switch, shared with the capture bars.
function CARRIER.On()
    return CludesUIDB and CludesUIDB.shifterBattlegroundUnlock or false
end

function CARRIER.Pos()
    return CludesUIDB and CludesUIDB.shifterCarrierPos
end

-- The live column, unless forbidden (a secret answer counts as forbidden).
function CARRIER.Frame()
    local widget = _G[CARRIER.name]
    if type(widget) ~= "table" or not widget.IsForbidden then
        return nil
    end
    local val = widget:IsForbidden()
    if issecretvalue(val) or val then
        return nil
    end
    return widget
end

-- Our spot while the feature is on; otherwise Blizzard's own anchor, and only
-- while ours is still on the column.
function CARRIER.Sync()
    local widget = CARRIER.Frame()
    if not widget then
        return
    end
    local place = CARRIER.On() and CARRIER.Pos()
    if not place and not CARRIER.moved then
        return
    end
    local success
    if place then
        local dx, dy = AnchorShift(place.point, "TOPRIGHT", CARRIER.w, CARRIER.h)
        success = SecureSetPoint(widget, "TOPRIGHT", place.relPoint, place.x + dx, place.y + dy)
    else
        success = SecureSetPointParent(widget, "TOPRIGHT", "TOPRIGHT", -10, 0)
    end
    if success then
        CARRIER.moved = place and true or false
    else
        mod.CombatQueue.Defer("ShifterCarriers", CARRIER.Sync)
    end
end

-- Hidden rect-only ghost the unlock mover attaches to; never visible. It sits
-- at the saved spot, or at the default one.
function CARRIER.PlaceProxy()
    local proxyFrame = CARRIER.proxy
    if not proxyFrame then
        proxyFrame = CreateFrame("Frame", nil, UIParent)
        proxyFrame:Hide()
        proxyFrame:SetSize(CARRIER.w, CARRIER.h)
        CARRIER.proxy = proxyFrame
    end
    local place = CARRIER.Pos()
    local skinData = CARRIER.defPos
    proxyFrame:ClearAllPoints()
    if place then
        proxyFrame:SetPoint(place.point, UIParent, place.relPoint, place.x, place.y)
    else
        proxyFrame:SetPoint(skinData[1], UIParent, skinData[2], skinData[3], skinData[4])
    end
    return proxyFrame
end

function CARRIER.Register()
    local MK = CludesUI.MakeUnlockElement
    if not MK or not CludesUI.RegisterUnlockElements then
        return
    end
    CludesUI:RegisterUnlockElements({
        MK({
            key = "CUI_FlagCarriers",
            label = "Flag Carriers",
            group = "Utilities",
            order = 645,
            noResize = true,
            noAnchorTarget = true,
            noAnchorTo = true,
            noSizeMatchTarget = true,
            moverBg = { r = 0.165, g = 0.11, b = 0.055 },
            subtitle = "Disable the Battleground Frames overlays in Shifter once done positioning",
            isHidden = function()
                if not CARRIER.On() or not _G[CARRIER.name] then
                    return true
                end
                return CludesUIDB and CludesUIDB.shifterBattlegroundHideOverlays or false
            end,
            getFrame = function()
                return CARRIER.proxy or CARRIER.PlaceProxy()
            end,
            -- The column's own rect changes with every carrier: fixed box.
            getSize = function()
                return CARRIER.w, CARRIER.h
            end,
            savePos = function(_, anchorPoint, relPoint, posX, posY)
                if not CludesUIDB then
                    CludesUIDB = {}
                end
                CludesUIDB.shifterCarrierPos =
                    { point = anchorPoint, relPoint = relPoint, x = posX, y = posY }
                CARRIER.PlaceProxy()
                CARRIER.Sync()
            end,
            loadPos = function()
                local place = CARRIER.Pos()
                if place then
                    return { point = place.point, relPoint = place.relPoint, x = place.x, y = place.y }
                end
                return nil
            end,
            clearPos = function()
                if CludesUIDB then
                    CludesUIDB.shifterCarrierPos = nil
                end
                CARRIER.PlaceProxy()
                CARRIER.Sync()
            end,
            applyPos = function()
                CARRIER.PlaceProxy()
                CARRIER.Sync()
            end,
        }),
    }, "CludesUIQoL")
end

-- Exposed for the options toggle: on, the column takes the saved spot; off,
-- Blizzard's own anchor comes back (after combat if need be).
function CludesUI._SyncShifterCarriers()
    CARRIER.Sync()
end

-------------------------------------------------------------------------------
--  Event-driven initialization
-------------------------------------------------------------------------------
local pendingAddons = {}
watcher = CreateFrame("Frame")

local function InitShifter()
    -- WoW Forever's Gamepad interface style drives Blizzard panels through its
    -- own D-pad focus and binding stack. Our hooks run inside a panel's show
    -- chain, so a panel opened from the radial menu leaves that stack tainted
    -- and the next gamepad Back gets a protected call blocked (Blizzard's
    -- forbidden popup then freezes the client). Dragging needs a mouse anyway,
    -- so nothing is hooked while that style is on (false on retail).
    if CludesUI.PadGamepadUI() then
        return
    end
    for index = 1, #PRELOADED do
        TryHook(PRELOADED[index])
    end
    for addon, frameList in pairs(ADDON_FRAMES) do
        if C_AddOns.IsAddOnLoaded(addon) then
            for index = 1, #frameList do
                TryHook(frameList[index])
            end
        else
            pendingAddons[addon] = frameList
        end
    end
    if next(pendingAddons) then
        watcher:RegisterEvent("ADDON_LOADED")
    end
    for frameName in pairs(adopted) do
        HookAdopted(frameName)
    end
    -- Scroll-wheel scaling: the modifier listener is owned by WheelArm.Sync
    -- and registered ONLY while a registered panel is open -- with everything
    -- closed a modifier press never enters Lua. Called here (not just on
    -- count edges) so a mid-session enable with a panel already open arms.
    WheelArm.Sync()
end

watcher:RegisterEvent("PLAYER_LOGIN")
watcher:SetScript("OnEvent", function(self, evt, arg1)
    if evt == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        if IsEnabled() then
            InitShifter()
        end
        RegisterLootUnlockElements()
        InitLootWindows()
        RegisterTopBarUnlockElement()
        if TopBarEnabled() then
            CludesUI._InitShifterTopBar()
        end
        CARRIER.Register()
        if CARRIER.On() then
            CARRIER.Sync()
        end
    elseif evt == "ADDON_LOADED" then
        local frameList = pendingAddons[arg1]
        if frameList then
            pendingAddons[arg1] = nil
            for index = 1, #frameList do
                TryHook(frameList[index])
            end
            if not next(pendingAddons) then
                self:UnregisterEvent("ADDON_LOADED")
            end
        end
    elseif evt == "MODIFIER_STATE_CHANGED" then
        UpdateWheelOverlay()
    end
end)

-- Exposed for the options toggle (mid-session enable without /reload)
function CludesUI._InitShifter()
    InitShifter()
end

-- Exposed for the options toggle (mid-session disable). Stops the modifier
-- key listener and parks the wheel overlay; re-enable re-runs InitShifter,
-- which registers the event again. Frame hooks are irreversible and stay
-- installed, but every hook body bails first-line while disabled.
function CludesUI._ShutdownShifter()
    watcher:UnregisterEvent("MODIFIER_STATE_CHANGED")
    UpdateWheelOverlay()
end

-- Exposed for the options reset button (positions AND zoom)
function CludesUI._ResetShifterPositions()
    if CludesUIDB then
        CludesUIDB.shifterPositions = nil
        CludesUIDB.shifterLootPositions = nil
        CludesUIDB.shifterTopBarPos = nil
        CludesUIDB.shifterCarrierPos = nil
        CludesUIDB.shifterScales = nil
    end
    wipe(tempPos)
    wipe(tempScale)
    -- No saved spots remain: the loot windows, the capture bars, the top bar
    -- and the flag carriers take Blizzard's own anchors back.
    for index = 1, #LOOT_WINDOWS do
        ReleaseLootWindow(LOOT_WINDOWS[index].name)
    end
    SyncTopBar()
    CARRIER.Sync()
end

-- Exposed for the options toggle (mid-session enable without /reload)
function CludesUI._InitShifterLootWindows()
    InitLootWindows()
end

-- Exposed for the options toggle, which turns its setting off first. The
-- windows it governs go to the next placement owner, or back to Blizzard's
-- own anchors; the capture bars follow the battleground switch.
function CludesUI._DisableShifterLootWindows()
    InitLootWindows()
end
