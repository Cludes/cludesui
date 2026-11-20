if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Minimap_Flyout.lua
--
--  The addon button flyout: junk filter, decoration strip and restore, the
--  grid layout, the Grow table, the panel, the toggle button and the button
--  row sizes and modes.
--  Reads the earlier Minimap files through ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIMinimap.lua or an earlier CUI_Minimap_*.lua file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local _addonVisible, cachedAddonButtons, SKIN = Inner._addonVisible, Inner.cachedAddonButtons, Inner.EBS
local ACC, flyoutOwnedFrames, GetFFD = Inner.EG, Inner.flyoutOwnedFrames, Inner.GetFFD
local QueueApplyAll, SetFlyoutPanel = Inner.QueueApplyAll, Inner.SetFlyoutPanel
local SetFlyoutToggle = Inner.SetFlyoutToggle

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._internals, which hands the value to every copy.
-- Assigned in CUI_Minimap_Layout.lua (see SetMOEvaluate), so the flyout
-- panels created here can fire it from OnShow/OnHide.
local MO_Evaluate
Inner.moEvaluateSetters[#Inner.moEvaluateSetters + 1] = function(val)
    MO_Evaluate = val
end

-------------------------------------------------------------------------------
--  Minimap Button Flyout
-------------------------------------------------------------------------------
local flyoutToggle = nil -- the square trigger button
local flyoutPanel = nil -- the popup grid container
Inner.flyoutToggleSetters[#Inner.flyoutToggleSetters + 1] = function(val)
    flyoutToggle = val
end
Inner.flyoutPanelSetters[#Inner.flyoutPanelSetters + 1] = function(val)
    flyoutPanel = val
end
local flyoutSavedParents = {} -- original parent/point data for restore
local flyoutSavedRegions = {} -- original region states for restore

local FLYOUT_BTN_SIZE = 24
local FLYOUT_PADDING = 4
local FLYOUT_COLS = 4

-- Textures that are decorative borders/backgrounds on minimap buttons
local MINIMAP_BTN_JUNK = {
    [136467] = true, -- UI-Minimap-Background
    [136430] = true, -- MiniMap-TrackingBorder
    [136477] = true, -- UI-Minimap-ZoomButton-Highlight (used on some buttons)
}
local MINIMAP_BTN_JUNK_PATH = {
    ["Interface\\Minimap\\MiniMap%-TrackingBorder"] = true,
    ["Interface\\Minimap\\UI%-Minimap%-Background"] = true,
    ["Interface\\Minimap\\UI%-Minimap%-ZoomButton%-Highlight"] = true,
}

local function IsJunkTexture(regionFrame)
    if not regionFrame or not regionFrame.IsObjectType or not regionFrame:IsObjectType("Texture") then
        return false
    end
    local texID = regionFrame.GetTextureFileID and regionFrame:GetTextureFileID()
    if texID and MINIMAP_BTN_JUNK[texID] then
        return true
    end
    local texPath = regionFrame:GetTexture()
    if texPath and type(texPath) == "string" then
        for pattern in pairs(MINIMAP_BTN_JUNK_PATH) do
            if texPath:match(pattern) then
                return true
            end
        end
    end
    return false
end

local function StripButtonDecorations(button)
    if not flyoutSavedRegions[button] then
        local saved = { junk = {} }
        for _, regionFrame in ipairs({ button:GetRegions() }) do
            if IsJunkTexture(regionFrame) then
                saved.junk[#saved.junk + 1] =
                    { region = regionFrame, alpha = regionFrame:GetAlpha(), shown = regionFrame:IsShown() }
            end
        end
        local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
        if highlight and IsJunkTexture(highlight) then
            saved.junk[#saved.junk + 1] =
                { region = highlight, alpha = highlight:GetAlpha(), shown = highlight:IsShown() }
        end
        -- Snapshot icon anchors/texcoord/size for RestoreButtonDecorations.
        local iconTex = button.icon or button.Icon
        if iconTex then
            local nPts = iconTex:GetNumPoints()
            local pts = {}
            for index = 1, nPts do
                pts[index] = { iconTex:GetPoint(index) }
            end
            saved.icon = iconTex
            saved.iconPoints = pts
            saved.iconTC = { iconTex:GetTexCoord() }
        end
        saved.btnW, saved.btnH = button:GetWidth(), button:GetHeight()
        flyoutSavedRegions[button] = saved
    end
    -- Junk hiding runs on every call; the snapshot above only once.
    for _, details in ipairs(flyoutSavedRegions[button].junk) do
        details.region:SetAlpha(0)
        details.region:Hide()
    end
end

local function RestoreButtonDecorations(button)
    local saved = flyoutSavedRegions[button]
    if not saved then
        return
    end
    for _, details in ipairs(saved.junk) do
        details.region:SetAlpha(details.alpha)
        if details.shown then
            details.region:Show()
        end
    end
    if saved.icon and saved.iconPoints then
        saved.icon:ClearAllPoints()
        for _, pt in ipairs(saved.iconPoints) do
            saved.icon:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5])
        end
        if saved.iconTC and #saved.iconTC >= 8 then
            saved.icon:SetTexCoord(unpack(saved.iconTC))
        end
    end
    if saved.btnW and saved.btnH then
        button:SetSize(saved.btnW, saved.btnH)
    end
    flyoutSavedRegions[button] = nil
end

local function IsUngrouped(button)
    -- A group of one has nothing to open: the only grouped button stands on
    -- the row by itself (decided per scan, see GatherMinimapButtons).
    if button == SKIN._soloAddonButton then
        return true
    end
    local mp = SKIN.db and SKIN.db.profile.minimap
    if not mp or not mp.ungroupedButtons then
        return false
    end
    local name = button:GetName()
    return name and mp.ungroupedButtons[name]
end

local function GetMinimapButtonLabel(button)
    local name = button:GetName() or ""
    return name:gsub("^LibDBIcon10_", "")
        :gsub("^Lib_GPI_Minimap_", "")
        :gsub("MinimapButton$", "")
        :gsub("_MinimapButton$", "")
end

local function CollectFlyoutButtons()
    local collected = {}
    for _, button in ipairs(cachedAddonButtons) do
        if _addonVisible[button] ~= false and not IsUngrouped(button) then
            collected[#collected + 1] = button
        end
    end
    table.sort(collected, function(lhs, rhs)
        return GetMinimapButtonLabel(lhs):lower() < GetMinimapButtonLabel(rhs):lower()
    end)
    return collected
end

local function GetAddonBtnSize()
    local mp = SKIN.db and SKIN.db.profile.minimap
    return mp and mp.addonBtnSize or FLYOUT_BTN_SIZE
end

-- CUI-look black box behind an addon button, on the button row and in the flyout grid alike.
-- A child frame of the button, so it is re-pinned just below the button on every layout:
-- the flyout's child loop lifts every child above the button, which would bury the icon.
-- EBS field, not local.
function SKIN._ShowAddonBtnBox(button)
    local skinData = GetFFD(button)
    if not skinData.ungroupBg then
        local ubg = CreateFrame("Frame", nil, button, "BackdropTemplate")
        ubg:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
        ubg:SetBackdropColor(0, 0, 0, 0.8)
        ubg:SetAllPoints(button)
        skinData.ungroupBg = ubg
    end
    local ubg = skinData.ungroupBg
    ubg:SetFrameStrata(button:GetFrameStrata())
    ubg:SetFrameLevel(button:GetFrameLevel() - 1)
    ubg:Show()
end

-- Raise popups an addon parents to its button after layout above the grid. The
-- button's own black box stays below it, where the layout pinned it.
function SKIN._RaiseLateFlyoutChildren(button)
    if not flyoutPanel or button:GetParent() ~= flyoutPanel then
        return
    end
    local combat = InCombatLockdown()
    local box = GetFFD(button).ungroupBg
    local function raise(widget, level)
        for _, childFrame in ipairs({ widget:GetChildren() }) do
            if childFrame ~= box and not (combat and childFrame:IsProtected()) then
                childFrame:SetFrameStrata("DIALOG")
                childFrame:SetFrameLevel(level)
                raise(childFrame, level + 1)
            end
        end
    end
    raise(button, flyoutPanel:GetFrameLevel() + 6)
end

-- Keep the grid open for a press on anything parented under it (forbidden frames never).
function SKIN._MouseOverFlyoutChild(panelFrame)
    local focus = GetMouseFoci()[1]
    while focus do
        if focus:IsForbidden() then
            return false
        end
        if focus == panelFrame then
            return true
        end
        focus = focus:GetParent()
    end
    return false
end

local function LayoutFlyoutButtons()
    if not flyoutPanel then
        return
    end
    local buttons = CollectFlyoutButtons()
    -- Same lockdown rule as HideMinimapChild: every per-button call in the loop below
    -- (SetParent/SetFrameStrata/SetPoint/SetSize/Show/SetFrameLevel) is protected and
    -- is blocked silently for a protected button, which would leave it half-moved with
    -- a flyoutSavedParents entry claiming it was placed. Drop those buttons from THIS
    -- pass -- before the saved-parent capture, so nothing is recorded for a move that
    -- never happened -- and queue the re-apply. ApplyMinimap invalidates and closes the
    -- flyout, so the next open rebuilds the full grid. The list is a fresh table per
    -- call, so compacting it in place is safe.
    if InCombatLockdown() then
        local kept = 0
        for index = 1, #buttons do
            local button = buttons[index]
            if button:IsProtected() then
                QueueApplyAll()
            else
                kept = kept + 1
                buttons[kept] = button
            end
        end
        for index = #buttons, kept + 1, -1 do
            buttons[index] = nil
        end
    end
    local total = #buttons
    if total == 0 then
        flyoutPanel:SetSize(1, 1)
        return
    end

    local btnSize = GetAddonBtnSize()
    -- CUI look: each cell gets the flat black box the ungrouped row buttons wear, so a
    -- button looks the same in the grid and on the row. Stock styles (and Button
    -- Backgrounds off) keep the stock-map ring around each icon.
    local mp = SKIN.db and SKIN.db.profile.minimap
    local boxes = not SKIN._MinimapBlizz() and not (mp and mp.btnBackgrounds == false)
    -- Boxes: the outer margin matches the gaps. Ring: margin=8, since the ring overlay
    -- overhangs each button by 3px, leaving 5px of visible clearance.
    local margin = boxes and FLYOUT_PADDING or 8
    local cols = math.min(total, FLYOUT_COLS)
    local rowList = math.ceil(total / cols)
    local pw = margin * 2 + cols * btnSize + (cols - 1) * FLYOUT_PADDING
    local ph = margin * 2 + rowList * btnSize + (rowList - 1) * FLYOUT_PADDING
    flyoutPanel:SetSize(pw, ph)

    for index, button in ipairs(buttons) do
        if not flyoutSavedParents[button] then
            local p1, relTo, p2, ox, oy = button:GetPoint(1)
            flyoutSavedParents[button] = {
                parent = button:GetParent(),
                strata = button:GetFrameStrata(),
                point = p1,
                relTo = relTo,
                relPoint = p2,
                x = ox,
                y = oy,
            }
        end

        local colour = (index - 1) % cols
        local row = math.floor((index - 1) / cols)
        local xOff = margin + colour * (btnSize + FLYOUT_PADDING)
        local yOff = -(margin + row * (btnSize + FLYOUT_PADDING))

        button:SetParent(flyoutPanel)
        -- Unlock fixed strata/level first (LibDBIcon locks these)
        if button.SetFixedFrameStrata then
            button:SetFixedFrameStrata(false)
        end
        if button.SetFixedFrameLevel then
            button:SetFixedFrameLevel(false)
        end
        button:SetFrameStrata("DIALOG")
        if button.SetFixedFrameStrata then
            button:SetFixedFrameStrata(true)
        end
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", flyoutPanel, "TOPLEFT", xOff, yOff)
        button:SetSize(btnSize, btnSize)
        SKIN._suppressVisTrack = true
        button:SetAlpha(1)
        button:Show()
        SKIN._suppressVisTrack = false
        button:SetFrameLevel(flyoutPanel:GetFrameLevel() + 5)
        if button.SetFixedFrameLevel then
            button:SetFixedFrameLevel(true)
        end
        StripButtonDecorations(button)
        -- Overlays left over from a previous ungroup cycle (or the other cell style)
        if not boxes and GetFFD(button).ungroupBg then
            GetFFD(button).ungroupBg:Hide()
        end
        if boxes and GetFFD(button).flyoutRing then
            GetFFD(button).flyoutRing:Hide()
        end
        if button._ungroupRing then
            button._ungroupRing:Hide()
        end
        -- Children must ride the same strata/level as the button.
        for _, childFrame in ipairs({ button:GetChildren() }) do
            childFrame:SetFrameStrata("DIALOG")
            childFrame:SetFrameLevel(flyoutPanel:GetFrameLevel() + 6)
        end
        if not GetFFD(button).lateChildHook then
            GetFFD(button).lateChildHook = true
            if button:HasScript("OnClick") then
                button:HookScript("OnClick", SKIN._RaiseLateFlyoutChildren)
            end
        end
        local iconTex = button.icon or button.Icon
        if not iconTex then
            for _, regionFrame in ipairs({ button:GetRegions() }) do
                if
                    regionFrame:IsObjectType("Texture")
                    and regionFrame:IsShown()
                    and regionFrame:GetAlpha() > 0
                    and not IsJunkTexture(regionFrame)
                then
                    iconTex = regionFrame
                    break
                end
            end
        end
        if iconTex then
            -- Same inset as the row: 3px inside the box, 2px inside the ring
            local inset = boxes and 3 or 2
            iconTex:ClearAllPoints()
            iconTex:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
            iconTex:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
            pcall(iconTex.SetTexCoord, iconTex, 0.05, 0.95, 0.05, 0.95)
            -- Foreign icon: no global SetTexCoord snap hook, so disable snap once here.
            if CludesUI.PP then
                CludesUI.PP.DisablePixelSnap(iconTex)
            end
        end
        if boxes then
            -- After the child loop above, which lifted the box over the icon
            SKIN._ShowAddonBtnBox(button)
        else
            if not GetFFD(button).flyoutRing then
                local ring = button:CreateTexture(nil, "OVERLAY", nil, 7)
                ring:SetAtlas("AdventureMap-combatally-ring")
                ring:SetPoint("TOPLEFT", button, "TOPLEFT", -3, 3)
                ring:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 3, -3)
                GetFFD(button).flyoutRing = ring
            end
            GetFFD(button).flyoutRing:Show()
        end
    end
end

-- Grow Tooltip/Popup: shared open-direction for all popups/tooltips off minimap
-- buttons (M+ portals, group flyout, custom tooltips). Auto follows Button Row
-- Position: vertical rows open left, horizontal rows open down. Namespace-scoped
-- (EBS field, not local). edge = anchor tuples (tooltip point,
-- anchor point, x, y) for corner-hung popups; center = centered on the facing edge
-- (vault tooltip); tt = named sides for ShowWidgetTooltip labels.
SKIN._Grow = {
    edge = {
        left = { "TOPRIGHT", "TOPLEFT", -4, 0 },
        right = { "TOPLEFT", "TOPRIGHT", 4, 0 },
        up = { "BOTTOMLEFT", "TOPLEFT", 0, 4 },
        down = { "TOPLEFT", "BOTTOMLEFT", 0, -4 },
    },
    center = {
        left = { "RIGHT", "LEFT", -4, 0 },
        right = { "LEFT", "RIGHT", 4, 0 },
        up = { "BOTTOM", "TOP", 0, 4 },
        down = { "TOP", "BOTTOM", 0, -4 },
    },
    tt = { left = "left", right = "right", up = "above", down = "below" },
}

function SKIN._Grow.Dir()
    local mp = SKIN.db and SKIN.db.profile.minimap
    local g = (mp and mp.flyoutGrowDir) or "auto"
    if g ~= "auto" then
        return g
    end
    local rp = (mp and mp.btnRowPosition) or "blUp"
    if rp == "blUp" or rp == "tlDown" or rp == "brUp" or rp == "trDown" then
        return "left"
    end
    return "down"
end

function SKIN._Grow.TT()
    return SKIN._Grow.tt[SKIN._Grow.Dir()] or "left"
end

local _flyoutBuilt = false

local function EnsureFlyoutPanel()
    if not flyoutPanel then
        -- Controller cursor: the shared overlay parent (UIParent without a
        -- controller UI, so nothing changes then); tracked once scripts are set.
        local overlayParent = CludesUI.OverlayParent()
        SetFlyoutPanel(CreateFrame("Frame", nil, overlayParent, "BackdropTemplate"))
        flyoutPanel:SetFrameStrata("DIALOG")
        flyoutPanel:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeSize = 1,
        })
        flyoutPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        flyoutPanel:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        -- Anchored per Grow Tooltip/Popup on every open (see ShowFlyoutPanel)
        flyoutPanel:SetClampedToScreen(true)
        flyoutOwnedFrames[flyoutPanel] = true
        -- Keep the mouseover stack in sync while this flyout opens/closes.
        flyoutPanel:HookScript("OnShow", function()
            if MO_Evaluate then
                MO_Evaluate()
            end
        end)
        flyoutPanel:HookScript("OnHide", function()
            if MO_Evaluate then
                MO_Evaluate()
            end
        end)
        -- Start hidden: frames spawn SHOWN and OnShow fires only on a real hide->show,
        -- so without this the first open never installs the watcher below.
        flyoutPanel:Hide()
        -- Click-away dismiss (matches options-panel dropdowns): closes on any left press
        -- outside the grid+toggle while shown. IsMouseButtonDown polls raw input state
        -- so clicks still land normally; the toggle is excluded so its own OnClick
        -- closes without a reopen race.
        flyoutPanel:HookScript("OnShow", function(self)
            self:SetScript("OnUpdate", function(frame)
                if
                    IsMouseButtonDown("LeftButton")
                    and not frame:IsMouseOver()
                    and not (flyoutToggle and flyoutToggle:IsMouseOver())
                    and not SKIN._MouseOverFlyoutChild(frame)
                then
                    frame:Hide()
                end
            end)
        end)
        flyoutPanel:HookScript("OnHide", function(self)
            self:SetScript("OnUpdate", nil)
        end)
        -- Controller cursor: its cancel button presses the toggle (closing the
        -- grid); the layer shows exactly while the grid does.
        if overlayParent ~= UIParent then
            flyoutPanel.CloseButton = flyoutToggle
            CludesUI.TrackOverlay(flyoutPanel)
        end
    end
end

-- Built once; buttons stay reparented into the grid permanently. Rebuilds only when the button list changes (new addon loaded, button ungrouped).
local function BuildFlyoutContents()
    EnsureFlyoutPanel()
    LayoutFlyoutButtons()
    _flyoutBuilt = true
end

local function InvalidateFlyout()
    _flyoutBuilt = false
end

-- Profile-swap refresh: invalidate for the next open, re-show buttons re-init hid.
_G._CUMIN_RefreshFlyout = function()
    InvalidateFlyout()
    if flyoutPanel and flyoutPanel:IsShown() then
        BuildFlyoutContents()
    end
    -- Re-assert alpha (profile swap re-hides via HideMinimapChild during re-init)
    for _, button in ipairs(cachedAddonButtons) do
        if button:GetParent() == flyoutPanel then
            button:SetAlpha(1)
            button:Show()
        end
    end
end

local function ShowFlyoutPanel()
    EnsureFlyoutPanel()
    -- Re-anchor per Grow Tooltip/Popup on every open (setting or Auto's row position can change). Left/right keep the toggle's bottom edge, up/down its left; 2px gap.
    local direction = SKIN._Grow.Dir()
    flyoutPanel:ClearAllPoints()
    if direction == "right" then
        flyoutPanel:SetPoint("BOTTOMLEFT", flyoutToggle, "BOTTOMRIGHT", 2, 0)
    elseif direction == "up" then
        flyoutPanel:SetPoint("BOTTOMLEFT", flyoutToggle, "TOPLEFT", 0, 2)
    elseif direction == "down" then
        flyoutPanel:SetPoint("TOPLEFT", flyoutToggle, "BOTTOMLEFT", 0, -2)
    else
        flyoutPanel:SetPoint("BOTTOMRIGHT", flyoutToggle, "BOTTOMLEFT", -2, 0)
    end
    -- Show BEFORE layout: the addon-button Show hook checks IsShown() to skip the
    -- alpha-zero path.
    flyoutPanel:Show()
    if not _flyoutBuilt then
        BuildFlyoutContents()
    end
end

local function HideFlyoutPanel()
    if flyoutPanel then
        flyoutPanel:Hide()
        -- Do NOT restore buttons or wipe saved parents; they stay parented here.
    end
end

local function ToggleFlyoutPanel()
    if flyoutPanel and flyoutPanel:IsShown() then
        HideFlyoutPanel()
    else
        ShowFlyoutPanel()
    end
end

local function GetInteractableBtnSize()
    local mp = SKIN.db and SKIN.db.profile.minimap
    return mp and mp.interactableBtnSize or 22
end

-- Row modes keyed by [MAP corner]+[growth dir] (blUp = left edge, bottom corner,
-- upward); vertical rows hug the outside of the left/right edge, horizontal rows run
-- above/below. point/rel = per-button anchor -> map anchor; dirX/dirY = growth vector;
-- awayX/awayY = Distance from Map push. PlaceRowButton/PlaceElement advance a cursor in snapped physical-pixel steps so icons stay flush at 0 spacing with equal gaps.
-- arc/arcDir: Blizzard Style walks the same row round the compass ring instead --
-- arc = the corner's angle on the circle (degrees, 0 = right, counter-clockwise),
-- arcDir = which way the row walks from it (+1 counter-clockwise, -1 clockwise).
local BTN_ROW_MODES = {
    -- Left edge (vertical)
    blUp = {
        point = "BOTTOMRIGHT",
        rel = "BOTTOMLEFT",
        dirX = 0,
        dirY = 1,
        awayX = -1,
        awayY = 0,
        arc = 225,
        arcDir = -1,
    },
    tlDown = {
        point = "TOPRIGHT",
        rel = "TOPLEFT",
        dirX = 0,
        dirY = -1,
        awayX = -1,
        awayY = 0,
        arc = 135,
        arcDir = 1,
    },
    -- Right edge (vertical)
    brUp = {
        point = "BOTTOMLEFT",
        rel = "BOTTOMRIGHT",
        dirX = 0,
        dirY = 1,
        awayX = 1,
        awayY = 0,
        arc = 315,
        arcDir = 1,
    },
    trDown = {
        point = "TOPLEFT",
        rel = "TOPRIGHT",
        dirX = 0,
        dirY = -1,
        awayX = 1,
        awayY = 0,
        arc = 45,
        arcDir = -1,
    },
    -- Above the map (horizontal)
    tlRight = {
        point = "BOTTOMLEFT",
        rel = "TOPLEFT",
        dirX = 1,
        dirY = 0,
        awayX = 0,
        awayY = 1,
        arc = 135,
        arcDir = -1,
    },
    trLeft = {
        point = "BOTTOMRIGHT",
        rel = "TOPRIGHT",
        dirX = -1,
        dirY = 0,
        awayX = 0,
        awayY = 1,
        arc = 45,
        arcDir = 1,
    },
    -- Below the map (horizontal)
    blRight = {
        point = "TOPLEFT",
        rel = "BOTTOMLEFT",
        dirX = 1,
        dirY = 0,
        awayX = 0,
        awayY = -1,
        arc = 225,
        arcDir = 1,
    },
    brLeft = {
        point = "TOPRIGHT",
        rel = "BOTTOMRIGHT",
        dirX = -1,
        dirY = 0,
        awayX = 0,
        awayY = -1,
        arc = 315,
        arcDir = -1,
    },
}

local function GetBtnRowMode(mp)
    return BTN_ROW_MODES[mp and mp.btnRowPosition or "blUp"] or BTN_ROW_MODES.blUp
end

-- Blizzard element row (tracking/calendar/mail/crafting): reuses BTN_ROW_MODES;
-- square shape only -- circle layout wraps around the clock instead.
local function GetElementRowMode(mp)
    return BTN_ROW_MODES[mp and mp.elementRowPosition or "tlDown"] or BTN_ROW_MODES.tlDown
end

-- Distance from Map push: left/right rows move horizontally, above/below vertically.
-- Icon Spacing is applied per link at placement. Forever Square's rows hang
-- from the frame's outer edge and start EBS.FV_ROW_AIR clear of it.
local function GetRowBase(mode, distance)
    local skinData = (distance or 0) + (SKIN._fvSquare and SKIN.FV_ROW_AIR or 0)
    return skinData * mode.awayX, skinData * mode.awayY
end

-- Scale for the custom tooltips on the unique minimap buttons (vault, friends,
-- calendar, mail, tracking, crafting, flyout toggle, portals).
local function GetCustomTooltipScale()
    local mp = SKIN.db and SKIN.db.profile.minimap
    return mp and mp.customTooltipScale or 1.0
end

local function CreateFlyoutToggle()
    if flyoutToggle then
        -- Re-apply the current accent so a later ApplyAll (e.g. at PLAYER_ENTERING_WORLD,
        -- after theme resolution mutated CLUDES_GREEN) picks up the right color.
        local EG2 = CludesUI.CLUDES_GREEN
        if flyoutToggle._norm then
            flyoutToggle._norm:SetVertexColor(EG2.r, EG2.g, EG2.b, 1)
        end
        if flyoutToggle._pushed then
            flyoutToggle._pushed:SetVertexColor(EG2.r, EG2.g, EG2.b, 1)
        end
        if flyoutToggle._hl then
            flyoutToggle._hl:SetVertexColor(EG2.r, EG2.g, EG2.b, 1)
        end
        return flyoutToggle
    end

    local button = CreateFrame("Button", nil, Minimap)
    local iconSize = GetInteractableBtnSize()
    button:SetSize(iconSize, iconSize)
    button:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMLEFT", 0, 0)
    button:SetFrameLevel(Minimap:GetFrameLevel() + 10)

    local norm = button:CreateTexture(nil, "ARTWORK")
    norm:SetAllPoints()
    norm:SetAtlas("Map-Filter-Button")
    norm:SetDesaturated(true)
    norm:SetVertexColor(ACC.r, ACC.g, ACC.b, 1)
    button:SetNormalTexture(norm)
    button._norm = norm

    local pushed = button:CreateTexture(nil, "ARTWORK")
    pushed:SetAllPoints()
    pushed:SetAtlas("Map-Filter-Button-down")
    pushed:SetDesaturated(true)
    pushed:SetVertexColor(ACC.r, ACC.g, ACC.b, 1)
    button:SetPushedTexture(pushed)
    button._pushed = pushed

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetAtlas("Map-Filter-Button")
    highlight:SetDesaturated(true)
    highlight:SetVertexColor(ACC.r, ACC.g, ACC.b, 1)
    highlight:SetAlpha(0.3)
    button:SetHighlightTexture(highlight)
    button._hl = highlight

    -- Keep the three textures synced to the accent. Vertex alpha stays 1; the highlight's SetAlpha(0.3) still applies on top since the two multiply.
    CludesUI.RegAccent({ type = "vertex", obj = norm })
    CludesUI.RegAccent({ type = "vertex", obj = pushed })
    CludesUI.RegAccent({ type = "vertex", obj = highlight })

    local backdrop = CreateFrame("Frame", nil, button, "BackdropTemplate")
    backdrop:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
    backdrop:SetBackdropColor(0, 0, 0, 0.8)
    backdrop:SetAllPoints(button)
    backdrop:SetFrameLevel(button:GetFrameLevel() - 1)
    button._bg = backdrop

    button:SetScript("OnClick", function(self)
        if GetFFD(self).freeMoveJustDragged then
            return
        end
        -- Opening the grid replaces the label tooltip (same as M+ Portals)
        CludesUI.HideWidgetTooltip(true)
        ToggleFlyoutPanel()
    end)
    button:SetScript("OnEnter", function(self)
        if flyoutPanel and flyoutPanel:IsShown() then
            return
        end
        if not GetFFD(self).freeMoveJustDragged and CludesUI.ShowWidgetTooltip then
            CludesUI.ShowWidgetTooltip(
                self,
                "Addon Buttons",
                { anchor = SKIN._Grow.TT(), scale = GetCustomTooltipScale() }
            )
        end
    end)
    button:SetScript("OnLeave", function(self)
        CludesUI.HideWidgetTooltip()
    end)

    -- Blizzard/addon hooks on minimap children can disable mouse; re-assert on Show.
    button:HookScript("OnShow", function(self)
        if not self:IsMouseEnabled() then
            self:EnableMouse(true)
        end
    end)

    SetFlyoutToggle(button)
    flyoutOwnedFrames[button] = true
    return button
end

Inner.BuildFlyoutContents, Inner.CollectFlyoutButtons = BuildFlyoutContents, CollectFlyoutButtons
Inner.CreateFlyoutToggle, Inner.flyoutSavedParents = CreateFlyoutToggle, flyoutSavedParents
Inner.flyoutSavedRegions, Inner.GetBtnRowMode = flyoutSavedRegions, GetBtnRowMode
Inner.GetCustomTooltipScale, Inner.GetElementRowMode = GetCustomTooltipScale, GetElementRowMode
Inner.GetInteractableBtnSize, Inner.GetRowBase = GetInteractableBtnSize, GetRowBase
Inner.HideFlyoutPanel, Inner.InvalidateFlyout = HideFlyoutPanel, InvalidateFlyout
Inner.IsJunkTexture, Inner.IsUngrouped = IsJunkTexture, IsUngrouped
Inner.RestoreButtonDecorations = RestoreButtonDecorations
Inner.StripButtonDecorations = StripButtonDecorations
Inner.broken = false
