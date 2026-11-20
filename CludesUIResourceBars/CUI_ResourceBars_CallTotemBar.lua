if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-- CUI_ResourceBars_CallTotemBar.lua
-- WoW FOREVER ONLY: Call Totem Bar. Blizzard's call totem bar
-- (MultiCastActionBarFrame: the Call of the Elements button, the four element
-- slots with their totem buttons, Totemic Recall) in the Totem Bar look, placed
-- by Unlock Mode instead of Edit Mode.
--
-- The bar stays Blizzard's: its own code fills, shows and hides it, and its
-- totem and spell buttons are secure. While the feature is on it is OURS in
-- four ways, all applied out of combat (a combat request waits for regen):
--   position  pinned to our holder (the unlock element) with the Edit Mode
--             system's saved base SetPoint / ClearAllPoints / SetScale, which
--             never flag Edit Mode's anchor pass; a layout apply's re-anchor
--             (ApplySystemAnchor) and Edit Mode's bottom bar stack, which
--             holds this bar too, are answered by re-pinning. Both also run
--             in combat (a form change, a mount, a level-up), where the
--             re-pin waits for regen, so the buttons hang from the holder,
--             never from the bar: wherever Edit Mode puts the bar frame
--             meanwhile, they stay
--   overlay   its Edit Mode selection at alpha 0 with no mouse, so Edit Mode
--             cannot select or drag it, and the bar frame's own mouse off,
--             so it takes no clicks where Edit Mode puts it in combat
--   layout    scale from Icon Size, and the shown buttons laid out in a row
--             or column with the chosen spacing (each totem button at its
--             element slot's spot); re-run after every Blizzard bar update,
--             which re-anchors the first slot and Totemic Recall
--   look      Blizzard's frame, ring and slot art faded, icons unmasked and
--             cropped square, our border frame on each button, the cooldown
--             numbers shown or hidden and sized by Show Timer / Timer Size
-- On a secure button it changes texture alpha, masks and texcoords, the
-- cooldown's countdown numbers and font, and (out of combat) its anchor;
-- nothing is written onto a Blizzard frame (every saved value lives in the
-- weak tables here). Off hands every piece back.
-- Off by default: nothing is hooked or changed until it is first turned on.
-- Shamans only: no other class has call totem spells.
-- Limits: a combat /reload or an in-combat bar update (a flyout page switch)
-- can leave the first slot and Totemic Recall where Blizzard puts them until
-- combat ends (most visible in a column); the totem buttons stay. If the bar
-- is snapped to another system in Edit Mode, resetting, reverting or hiding
-- that system re-pins the bar here, but Edit Mode records the bar's current
-- spot as its own, so saving the layout then keeps it for when this is
-- turned off.

local _, mod = ...
local CludesUI = _G.CludesUI
if not (CludesUI and CludesUI.IS_FOREVER) then
    return
end
local barFrame = _G.MultiCastActionBarFrame
if not barFrame then
    return
end
local _, playerClass = UnitClass("player")
if playerClass ~= "SHAMAN" then
    return
end

local UNLOCK_KEY = "ERB_CallTotemBar"
local BTN = 30 -- the bar's button size, in its own units
local MAX_BUTTONS = 6 -- Call of the Elements, four slots, Totemic Recall
local ZOOM = 0.08
local FONT_NAME = "ERB_CallTotemCountdownFont"

local SUMMON = _G.MultiCastSummonSpellButton
local RECALL = _G.MultiCastRecallSpellButton
local SLOT, ACT = {}, {}
for index = 1, 4 do
    SLOT[index] = _G["MultiCastSlotButton" .. index]
end
for index = 1, 12 do
    ACT[index] = _G["MultiCastActionButton" .. index]
end

local holderFrame -- our frame: the unlock element the bar is pinned to
local owned = false -- the bar is anchored, laid out and skinned by us
local hooked = false
local home -- the bar's own scale, size and strata before we took it
local sequence = {} -- scratch: the shown buttons in layout order
local savedAlpha = setmetatable({}, { __mode = "k" }) -- faded texture -> its alpha
local unmasked = setmetatable({}, { __mode = "k" }) -- icon -> the mask we removed
local borders = setmetatable({}, { __mode = "k" }) -- button -> our border frame
local homeFont = setmetatable({}, { __mode = "k" }) -- cooldown -> its countdown font object's name (false: none)

-- Countdown numbers: a named font object the cooldowns render with.
local cdFont = CreateFont(FONT_NAME)
cdFont:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")

-------------------------------------------------------------------------------
--  Settings access
-------------------------------------------------------------------------------

local function P()
    local ERB = mod.ERB
    local saved = ERB and ERB.db
    local profile = saved and saved.profile
    return profile and profile.callTotemBar or nil
end

local function Blocked()
    return InCombatLockdown()
end

local function Queue(key, func)
    mod.CombatQueue.Defer(key, func)
end

-------------------------------------------------------------------------------
--  Look
-------------------------------------------------------------------------------

local function Fade(texture)
    if not texture then
        return
    end
    if savedAlpha[texture] == nil then
        local alpha = texture:GetAlpha()
        if issecretvalue(alpha) then
            alpha = 1
        end
        savedAlpha[texture] = alpha
    end
    texture:SetAlpha(0)
end

local function Unfade(texture)
    local a = texture and savedAlpha[texture]
    if a == nil then
        return
    end
    texture:SetAlpha(a)
    savedAlpha[texture] = nil
end

-- The art a button carries in Blizzard's look: the icon frame, its slot art,
-- the element ring (overlayTex) and, on the two spell buttons, their ring
-- highlight. Region names follow the templates.
local function ArtOf(button, func)
    func(button:GetNormalTexture())
    func(button.SlotArt)
    func(button.SlotBackground)
    func(button.overlayTex)
    local name = button:GetName()
    if name and (button == SUMMON or button == RECALL) then
        func(_G[name .. "Highlight"])
    end
end

local function SkinButton(button, cfg)
    ArtOf(button, Fade)
    local iconTex = button.icon
    if iconTex then
        -- A masked texture rejects SetTexCoord: the mask goes first.
        local mask = button.IconMask
        if mask and not unmasked[iconTex] then
            if pcall(iconTex.RemoveMaskTexture, iconTex, mask) then
                unmasked[iconTex] = mask
            end
        end
        pcall(iconTex.SetTexCoord, iconTex, ZOOM, 1 - ZOOM, ZOOM, 1 - ZOOM)
    end
    local cd = button.cooldown
    if cd then
        cd:SetHideCountdownNumbers(not cfg.showTimer)
        if cfg.showTimer and cd.SetCountdownFont then
            if homeFont[cd] == nil then
                local fontStr = cd.GetCountdownFontString and cd:GetCountdownFontString()
                local object = fontStr and fontStr:GetFontObject()
                homeFont[cd] = (object and object:GetName()) or false
            end
            cd:SetCountdownFont(FONT_NAME)
        end
    end
    -- Our border frame, in the button's own scale like the active bar's.
    local o = borders[button]
    if not o then
        o = CreateFrame("Frame", nil, button)
        o:SetAllPoints(button)
        borders[button] = o
    end
    o:SetFrameLevel(
        cfg.borderBehind and math.max(0, button:GetFrameLevel() - 1) or (button:GetFrameLevel() + 3)
    )
    o:Show()
    local bs = cfg.borderSize or 0
    local texKey = cfg.borderTexture or "solid"
    CludesUI.ApplyBorderStyle(
        o,
        bs,
        cfg.borderR or 0,
        cfg.borderG or 0,
        cfg.borderB or 0,
        cfg.borderA or 1,
        texKey,
        cfg.borderTextureOffset,
        cfg.borderTextureOffsetY,
        cfg.borderTextureShiftX,
        cfg.borderTextureShiftY,
        "resourcebars",
        bs,
        nil,
        CludesUI.BorderPx(cfg.borderSizePx, bs, texKey)
    )
end

-- hideNumbers: the stock countdown state (the totem buttons follow Blizzard's
-- Show Numbers for Cooldowns setting; the two spell buttons always show them).
local function UnskinButton(button, hideNumbers)
    ArtOf(button, Unfade)
    local iconTex = button.icon
    if iconTex then
        local mask = unmasked[iconTex]
        if mask then
            pcall(iconTex.AddMaskTexture, iconTex, mask)
            unmasked[iconTex] = nil
        end
        pcall(iconTex.SetTexCoord, iconTex, 0, 1, 0, 1)
    end
    local cd = button.cooldown
    if cd then
        cd:SetHideCountdownNumbers(hideNumbers)
        local fontName = homeFont[cd]
        if fontName and cd.SetCountdownFont then
            cd:SetCountdownFont(fontName)
        end
    end
    local o = borders[button]
    if o then
        o:Hide()
    end
end

local function SkinAll(cfg)
    local scale = (cfg.iconSize or 30) / BTN
    local size = math.max(6, math.floor((cfg.timerSize or 11) / scale + 0.5))
    cdFont:SetFont(mod.GetRBFont(), size, CludesUI.GetFontOutlineFlag("resourceBars"))
    if SUMMON then
        SkinButton(SUMMON, cfg)
    end
    if RECALL then
        SkinButton(RECALL, cfg)
    end
    for index = 1, #ACT do
        SkinButton(ACT[index], cfg)
    end
    for index = 1, 4 do
        Fade(SLOT[index].overlayTex)
    end
end

local function UnskinAll()
    if SUMMON then
        UnskinButton(SUMMON, false)
    end
    if RECALL then
        UnskinButton(RECALL, false)
    end
    local hideNumbers = not GetCVarBool("countdownForCooldowns")
    for index = 1, #ACT do
        UnskinButton(ACT[index], hideNumbers)
    end
    for index = 1, 4 do
        Unfade(SLOT[index].overlayTex)
    end
end

-------------------------------------------------------------------------------
--  Position and layout (out of combat only)
-------------------------------------------------------------------------------

local function HolderSize(cfg)
    local iconSize = (cfg and cfg.iconSize) or 30
    local spacing = (cfg and cfg.spacing) or 2
    local length = iconSize * MAX_BUTTONS + spacing * (MAX_BUTTONS - 1)
    if cfg and cfg.orientation == "VERTICAL" then
        return iconSize, length
    end
    return length, iconSize
end

-- Pin the bar's top-left corner to the holder's, through the system's base
-- methods (Blizzard's SetPoint / ClearAllPoints overrides flag Edit Mode).
local function PinBar()
    CludesUI.ClearFramePoints(barFrame)
    CludesUI.SetFramePoint(barFrame, "TOPLEFT", holderFrame, "TOPLEFT", 0, 0)
end

-- The shown buttons in a row (left to right) or a column (top to bottom), each
-- totem button at its element slot's spot. Every button hangs from the
-- holder's top-left corner, where the bar's own is pinned, never from the
-- bar: Edit Mode re-anchors the bar frame in combat too (its bottom bar stack
-- on a form change or a mount, its layout apply on a level-up), when the
-- re-pin has to wait for regen, and a button on the holder stays through it.
-- Blizzard's updates re-anchor the first slot by its BOTTOMLEFT and Totemic
-- Recall by its LEFT, so those two points are the ones used here: an update
-- that lands before our pass moves them, it never pulls them between two
-- anchors.
local function Layout(cfg)
    local iconSize = cfg.iconSize or 30
    local scale = iconSize / BTN
    local spacing = cfg.spacing or 2
    local Pix = CludesUI.PP
    if Pix and Pix.Snap then
        spacing = Pix.Snap(spacing)
    end
    local gap = spacing / scale
    local vertical = cfg.orientation == "VERTICAL"

    wipe(sequence)
    if SUMMON and SUMMON:IsShown() then
        sequence[#sequence + 1] = SUMMON
    end
    local num = barFrame.numActiveSlots or 0
    if issecretvalue(num) then
        num = 0
    end
    for index = 1, num do
        sequence[#sequence + 1] = SLOT[index]
    end
    if RECALL and RECALL:IsShown() then
        sequence[#sequence + 1] = RECALL
    end
    local total = #sequence
    local length = total > 0 and (total * BTN + (total - 1) * gap) or BTN

    for index = 1, total do
        local widget = sequence[index]
        local off = (index - 1) * (BTN + gap)
        local posX = vertical and 0 or off
        local posY = -(vertical and off or 0) - BTN
        widget:ClearAllPoints()
        if widget == RECALL then
            widget:SetPoint("LEFT", holderFrame, "TOPLEFT", posX, posY + BTN / 2)
        else
            widget:SetPoint("BOTTOMLEFT", holderFrame, "TOPLEFT", posX, posY)
        end
    end
    -- The element slots follow Call of the Elements when it shows.
    local first = (SUMMON and sequence[1] == SUMMON) and 1 or 0
    for index = 1, #ACT do
        local widget = ACT[index]
        local off = (first + (index - 1) % 4) * (BTN + gap)
        widget:ClearAllPoints()
        widget:SetPoint(
            "CENTER",
            holderFrame,
            "TOPLEFT",
            (vertical and 0 or off) + BTN / 2,
            -(vertical and off or 0) - BTN / 2
        )
    end

    if vertical then
        barFrame:SetSize(BTN, length)
    else
        barFrame:SetSize(length, BTN)
    end
    CludesUI.SetFrameScale(barFrame, scale)
    barFrame:SetFrameStrata(cfg.frameStrata or "MEDIUM")
    PinBar()
end

-- Blizzard's own anchors (the template's, and its update rules for the first
-- slot and Totemic Recall), for the hand-back.
local function RestoreLayout()
    if SUMMON then
        SUMMON:ClearAllPoints()
        SUMMON:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", 3, 3)
    end
    local posX = (SUMMON and SUMMON:IsShown()) and (SUMMON:GetWidth() + 8 + 3) or 3
    SLOT[1]:ClearAllPoints()
    SLOT[1]:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", posX, 3)
    for index = 2, 4 do
        SLOT[index]:ClearAllPoints()
        SLOT[index]:SetPoint("LEFT", SLOT[index - 1], "RIGHT", 8, 0)
    end
    for index = 1, #ACT do
        local widget = ACT[index]
        widget:ClearAllPoints()
        if (index - 1) % 4 == 0 then
            widget:SetPoint("LEFT", _G["MultiCastActionPage" .. (math.floor((index - 1) / 4) + 1)], "LEFT", 0, 0)
        else
            widget:SetPoint("LEFT", ACT[index - 1], "RIGHT", 8, 0)
        end
    end
    if RECALL then
        local num = barFrame.numActiveSlots or 0
        if issecretvalue(num) then
            num = 0
        end
        RECALL:ClearAllPoints()
        RECALL:SetPoint("LEFT", num > 0 and SLOT[num] or ACT[4], "RIGHT", 8, 0)
    end
end

-- The holder's spot: another element's anchor, the saved Unlock Mode spot, or
-- the default (where Blizzard's own default puts the bar's right edge).
local function PlaceHolder(cfg)
    -- Unlock Mode owns a placed holder while it is open.
    if CludesUI._unlockActive and holderFrame:GetNumPoints() > 0 then
        return
    end
    local place = cfg.unlockPos
    if place and place.point then
        if CludesUI.IsUnlockAnchored(UNLOCK_KEY) and holderFrame:GetLeft() then
            return
        end
        local sx, sy = mod.SnapXY(place.x or 0, place.y or 0, holderFrame, place)
        holderFrame:ClearAllPoints()
        holderFrame:SetPoint(place.point, UIParent, place.relPoint or place.point, sx, sy)
    elseif not CludesUI.IsUnlockAnchored(UNLOCK_KEY) then
        holderFrame:ClearAllPoints()
        holderFrame:SetPoint("RIGHT", UIParent, "BOTTOM", -28, 128)
    end
end

-------------------------------------------------------------------------------
--  Ownership
-------------------------------------------------------------------------------

local Refresh

-- Blizzard's layout apply re-anchors the system; a bar update re-anchors the
-- first slot and Totemic Recall and re-sets the art. Both are answered while
-- the bar is ours (in combat, at regen).
local function OnSystemAnchor()
    if not owned then
        return
    end
    if Blocked() then
        Queue("CTRefresh", Refresh)
        return
    end
    PinBar()
end

local function OnBarUpdate()
    if not owned then
        return
    end
    if Blocked() then
        Queue("CTRefresh", Refresh)
        return
    end
    Refresh()
end

-- Blizzard hangs its flyout arrow above the hovered slot or Call of the
-- Elements button; in a column that covers the button above (a click there
-- opens the flyout), so a vertical bar gets it beside the button instead. The
-- arrow is not secure, so this holds in combat too. Blizzard adds its point on
-- every show without clearing, so each show is cleared and re-set here, and
-- put back above the button once the bar is no longer a column.
local arrowMoved = false
local function OnFlyoutArrow(arrow, _, hostFrame)
    if not (arrow and hostFrame) or arrow:GetParent() ~= hostFrame then
        return
    end
    local c = owned and P()
    local side = (c and c.orientation == "VERTICAL") or false
    if not (side or arrowMoved) then
        return
    end
    arrowMoved = side
    arrow:ClearAllPoints()
    if side then
        arrow:SetPoint("LEFT", hostFrame, "RIGHT", 0, 0)
    else
        arrow:SetPoint("BOTTOM", hostFrame, "TOP", 0, 0)
    end
end

local function Hook()
    if hooked then
        return
    end
    hooked = true
    hooksecurefunc(barFrame, "ApplySystemAnchor", OnSystemAnchor)
    -- A snap break (Edit Mode resetting, reverting or hiding the system the bar
    -- was snapped to) re-anchors the bar to UIParent: re-pin it the same way.
    if barFrame.BreakFrameSnap then
        hooksecurefunc(barFrame, "BreakFrameSnap", OnSystemAnchor)
    end
    -- The bar is one of the bottom action bars Edit Mode stacks: its stack
    -- pass (after every layout apply, on this bar's own show and hide, on a
    -- status bar change) moves a shown bar that sits at its default spot.
    local mgr = _G.EditModeManagerFrame
    if mgr and mgr.UpdateBottomActionBarPositions then
        hooksecurefunc(mgr, "UpdateBottomActionBarPositions", OnSystemAnchor)
    end
    hooksecurefunc("MultiCastActionBarFrame_Update", OnBarUpdate)
    if _G.MultiCastFlyoutFrameOpenButton_Show then
        hooksecurefunc("MultiCastFlyoutFrameOpenButton_Show", OnFlyoutArrow)
    end
end

-- Edit Mode never resets the selection's alpha or mouse, so one write holds.
local selMouse
local function SuppressSelection()
    local sel = barFrame.Selection
    if not sel then
        return
    end
    Fade(sel)
    if selMouse == nil then
        selMouse = sel:IsMouseEnabled()
    end
    sel:EnableMouse(false)
end

local function ReleaseSelection()
    local sel = barFrame.Selection
    if not sel then
        return
    end
    Unfade(sel)
    if selMouse ~= nil then
        sel:EnableMouse(selMouse)
    end
end

-- The bar frame's own mouse only fills the gaps between Blizzard's buttons.
-- Off while the bar is ours: Edit Mode can leave the frame somewhere else
-- for a whole fight, where it would take the clicks meant for what is under
-- it. This one frame only, put back as each takeover found it.
local barMouse
local function SuppressBarMouse()
    barMouse = barFrame:IsMouseEnabled()
    barFrame:EnableMouse(false)
end

local function ReleaseBarMouse()
    if barMouse ~= nil then
        barFrame:EnableMouse(barMouse)
    end
end

Refresh = function()
    local profile = P()
    if not (owned and profile) then
        return
    end
    Layout(profile)
    SkinAll(profile)
end

local function Release()
    if not owned then
        return
    end
    if Blocked() then
        Queue("CTApply", mod.CT_Apply)
        return
    end
    owned = false
    UnskinAll()
    RestoreLayout()
    ReleaseSelection()
    ReleaseBarMouse()
    CludesUI.SetFrameScale(barFrame, home.scale)
    barFrame:SetSize(home.w, home.h)
    barFrame:SetFrameStrata(home.strata)
    -- Back to the Edit Mode layout's spot (read from the system's own record).
    local details = barFrame.systemInfo
    local ai = details and details.anchorInfo
    CludesUI.ClearFramePoints(barFrame)
    if ai then
        local s = barFrame:GetScale()
        CludesUI.SetFramePoint(barFrame, ai.point, ai.relativeTo, ai.relativePoint, ai.offsetX / s, ai.offsetY / s)
        local ai2 = details.anchorInfo2
        if ai2 then
            CludesUI.SetFramePoint(
                barFrame,
                ai2.point,
                ai2.relativeTo,
                ai2.relativePoint,
                ai2.offsetX / s,
                ai2.offsetY / s
            )
        end
    else
        CludesUI.SetFramePoint(barFrame, "RIGHT", UIParent, "BOTTOM", -28, 128)
    end
end

function mod.CT_Apply()
    local profile = P()
    if not (profile and profile.enabled) then
        Release()
        -- In combat Release waits for regen with the bar still pinned to the
        -- holder (which that makes protected); its queued pass hides it then.
        if holderFrame and not owned then
            holderFrame:Hide()
        end
        return
    end
    if Blocked() then
        Queue("CTApply", mod.CT_Apply)
        return
    end
    if not holderFrame then
        holderFrame = CreateFrame("Frame", "ERB_CallTotemBarFrame", UIParent)
        holderFrame:SetFrameLevel(15)
        -- Re-register so unlock mode picks up the new frame
        if _G._CURB_RegisterUnlock then
            _G._CURB_RegisterUnlock()
        end
    end
    holderFrame:SetSize(HolderSize(profile))
    holderFrame:Show()
    PlaceHolder(profile)
    Hook()
    if not owned then
        if not home then
            local wid, hgt = barFrame:GetSize()
            home = { scale = barFrame:GetScale(), w = wid, h = hgt, strata = barFrame:GetFrameStrata() }
        end
        owned = true
        SuppressSelection()
        SuppressBarMouse()
    end
    Refresh()
end

-------------------------------------------------------------------------------
--  Unlock element
-------------------------------------------------------------------------------

function mod.CT_MakeUnlockElement(MK)
    if not MK then
        return nil
    end
    local function save(key, anchorPoint, relPoint, posX, posY)
        if not anchorPoint then
            return
        end
        local profile = P()
        if not profile then
            return
        end
        profile.unlockPos = { point = anchorPoint, relPoint = relPoint or anchorPoint, x = posX, y = posY }
        if not CludesUI._unlockActive and holderFrame then
            holderFrame:ClearAllPoints()
            holderFrame:SetPoint(anchorPoint, UIParent, relPoint or anchorPoint, posX, posY)
        end
    end
    local function load()
        local profile = P()
        local place = profile and profile.unlockPos
        if not place then
            return nil
        end
        return { point = place.point, relPoint = place.relPoint or place.point, x = place.x, y = place.y }
    end
    local function clear()
        local profile = P()
        if not profile then
            return
        end
        profile.unlockPos = nil
    end
    local function apply()
        local profile = P()
        local place = profile and profile.unlockPos
        if not (place and holderFrame) then
            return
        end
        local sx, sy = mod.SnapXY(place.x, place.y, holderFrame, place)
        holderFrame:ClearAllPoints()
        holderFrame:SetPoint(place.point, UIParent, place.relPoint or place.point, sx, sy)
    end
    return MK({
        key = UNLOCK_KEY,
        label = "Call Totem Bar",
        group = "Resource Bars",
        order = 509,
        noResize = true,
        noAnchorTarget = true,
        isHidden = function()
            local profile = P()
            return not (profile and profile.enabled)
        end,
        getFrame = function()
            return holderFrame
        end,
        getSize = function()
            return HolderSize(P())
        end,
        savePos = save,
        loadPos = load,
        clearPos = clear,
        applyPos = apply,
    })
end
