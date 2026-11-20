if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  Character Sheet Socket Panel
--
--  A bounded row of socket icons in the blank strip along the bottom
--  edge of the CUI-skinned character sheet, right-aligned. Under the stock
--  styles (Blizzard / Classic) it hangs below Blizzard's sheet instead, a
--  plate in the bottom tabs' own art at the bottom-right corner, with
--  Blizzard's item-button, menu and page-arrow art. Each icon is one
--  socket on a currently-equipped item:
--  filled sockets paint the gem, empty sockets paint the empty-socket texture.
--  Clicking a socket opens a flyout of socketable bag gems; clicking a gem
--  socket-sequences it into that exact socket index.
--
--  Zero cost when the sheet is closed: everything is built lazily on first
--  show, and WoW events are registered only while the Character tab is
--  shown (plus one ADDON_LOADED that waits for the socketing UI).
--  Zero taint: all UI frames are ours; Blizzard frames are HookScript-only
--  apart from the sanctioned SetUIPanelAttribute seat on ItemSocketingFrame;
--  no custom keys are written onto Blizzard-owned frames.
--------------------------------------------------------------------------------
local ADDON_NAME, mod = ...

-- Probe-and-fallback API locals. On Midnight/PTR some socket-session calls are
-- namespaced under C_ItemSocketInfo and some remain bare globals; resolve each
-- once here so a missing API simply yields nil (the panel stays empty).
local CIS = _G.C_ItemSocketInfo
local GetNumSockets = (CIS and CIS.GetNumSockets) or _G.GetNumSockets
local ClickSocketBtn = (CIS and CIS.ClickSocketButton) or _G.ClickSocketButton
local AcceptSocketsFn = (CIS and CIS.AcceptSockets) or _G.AcceptSockets
local CloseSocketFn = (CIS and CIS.CloseSocketInfo) or _G.CloseSocketInfo
local SocketInvItem = (CIS and CIS.SocketInventoryItem) or _G.SocketInventoryItem
local GetNewSocketInfoFn = (CIS and CIS.GetNewSocketInfo) or _G.GetNewSocketInfo
local GetItemNumSockets = C_Item and C_Item.GetItemNumSockets
local GetItemGemFn = C_Item and C_Item.GetItemGem
local GetItemStatsFn = C_Item and C_Item.GetItemStats
local GetInfoInstant = C_Item and C_Item.GetItemInfoInstant
local GetIconByID = C_Item and C_Item.GetItemIconByID
local GetItemCountFn = C_Item.GetItemCount
local CClear = _G.ClearCursor
local CHasItem = _G.CursorHasItem

-- Constants. SIZE, PAD, PAGE_BUTTON_W, EDGE_X, ICON_Y, FLY_PAD and
-- FLY_BOTTOM hold the CludesUI look's layout; the bootstrap swaps in the
-- stock plate's values once, at login, when the latched sheet style is
-- Blizzard or Classic (STOCK), before anything is built.
local SIZE = 28
local PAD = 4
local MAX_SOCKET_ICONS = 6
local PAGE_BUTTON_W = 12
local EDGE_X = 0 -- padding between the panel's edges and its first/last icon
local ICON_Y = 0 -- vertical offset of the icon row inside the panel
local FLY_PAD = 4 -- flyout row inset (left, right, top)
local FLY_BOTTOM = 4 -- flyout space below the last row
local MIN_W = 0 -- narrowest panel (the stock plate's two tab end caps)
local STOCK = false
local ROW_H = 20 -- gem flyout row height
local FLYOUT_W = 240
local MAX_FLYOUT_ROWS = 12 -- flyout caps here; extra gems scroll with the wheel
local GEM_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Gem) or 3
local EMPTY_SOCKET_TEX = "Interface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic"

-- Character-sheet order: left column, right column, then weapons.
-- Skip shirt/tabard; each item's sockets stay in socket-index order.
local SLOTS = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17 }

-- State (all plain Lua tables / our own frames -- nothing lives on Blizzard frames)
local sockets = {} -- ordered list of { slot, socketIndex, gemLink, emptyName }
local iconPool = {} -- pooled socket icon buttons
local gemCache = {} -- deduped bag gems: { itemID, link, tex }
local relevantItems = {} -- itemID -> true for equipped socketed items + their gems
local gemRows = {} -- pooled flyout rows
local waiting = nil -- in-flight socket action
local panelFrame -- the panel frame
local seasonPane -- optional vault / Midnight folio shortcuts
local gemMenu -- the gem flyout frame
local clickCatcher -- full-screen click-catcher behind the flyout
local eventFrame -- our event frame
local built = false
local shownEvents = false
local gemsStale = true
local pendingGemLoads = {} -- itemID -> true: bag gems whose data load we requested
local socketLoadRequested = {} -- gem itemID -> true: equipped-gem data loads we requested
local activeIcon = nil -- icon whose flyout is currently open
local pageIndex = 0
local lastPage, nextPage
local flyoutScroll = 0 -- top gem index offset when the gem list overflows MAX_FLYOUT_ROWS
local menuHoverMode = false -- flyout opened by hovering an empty socket (auto-closes on leave)
local ourSession = false -- a socketing session WE opened is (or may still be) live

--------------------------------------------------------------------------------
--  Helpers
--------------------------------------------------------------------------------

-- Rarity -> border color (local copy; do not reach into CharacterSheet.lua).
local function GemBorderColor(rarity)
    if (rarity or 0) >= 3 then
        return 1.00, 0.82, 0.00, 1 -- gold
    end
    return 0.75, 0.75, 0.75, 1 -- silver
end

-- Build a short "+16 Versatility & +7 Critical Strike" summary for a gem.
local function GetGemStatText(gemLinkText)
    if not gemLinkText then
        return ""
    end
    local pieces
    if GetItemStatsFn then
        local stats = GetItemStatsFn(gemLinkText)
        if stats then
            -- Stat keys are global-string tokens ("ITEM_MOD_HASTE_RATING_SHORT",
            -- "ITEM_MOD_VERSATILITY", ...); _G[key] is the localized stat name.
            for keyName, val in pairs(stats) do
                if type(keyName) == "string" and type(val) == "number" and val > 0 and keyName:find("^ITEM_MOD_") then
                    local label = _G[keyName]
                    if type(label) == "string" and label ~= "" then
                        pieces = pieces or {}
                        pieces[#pieces + 1] = "+" .. val .. " " .. label
                    end
                end
            end
        end
    end
    if pieces and #pieces > 0 then
        table.sort(pieces)
        return table.concat(pieces, " & ")
    end
    -- Fallback: the gem's own name.
    if C_Item and C_Item.GetItemInfo then
        local nm = C_Item.GetItemInfo(gemLinkText)
        if nm then
            return nm
        end
    end
    return "Gem"
end

-- Find the first bag slot currently holding the given gem itemID.
local function FindBagSlotForItem(itemId)
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then
        return nil
    end
    local maxBag = _G.NUM_BAG_SLOTS or 4
    for bagId = 0, maxBag do
        local n = C_Container.GetContainerNumSlots(bagId) or 0
        for slotId = 1, n do
            -- GetContainerItemID reads the slot directly and works before the
            -- item's data is cached; GetContainerItemInfo returns nil for an
            -- item this client has never seen (e.g. fresh from the mailbox).
            local ident = C_Container.GetContainerItemID and C_Container.GetContainerItemID(bagId, slotId)
            if not ident then
                local details = C_Container.GetContainerItemInfo(bagId, slotId)
                ident = details and details.itemID
            end
            if ident == itemId then
                return bagId, slotId
            end
        end
    end
    return nil
end

-- Scan bags for socketable gems (lazy; only when a flyout opens with dirty cache).
local function ScanBagGems()
    for i = #gemCache, 1, -1 do
        gemCache[i] = nil
    end
    if
        not (
            C_Container
            and C_Container.GetContainerNumSlots
            and C_Container.GetContainerItemInfo
            and GetInfoInstant
        )
    then
        gemsStale = false
        return
    end
    local seen = {}
    local maxBag = _G.NUM_BAG_SLOTS or 4
    for bagId = 0, maxBag do
        local n = C_Container.GetContainerNumSlots(bagId) or 0
        for slotId = 1, n do
            -- GetContainerItemID works before the item's data is cached;
            -- GetContainerItemInfo returns nil for an item this client has
            -- never seen (e.g. a gem fresh from the mailbox), which made new
            -- gems invisible until something else forced the cache.
            local itemId = C_Container.GetContainerItemID and C_Container.GetContainerItemID(bagId, slotId)
            if not itemId then
                local details = C_Container.GetContainerItemInfo(bagId, slotId)
                itemId = details and details.itemID
            end
            if itemId and not seen[itemId] then
                local _, _, _, _, texture, classID = GetInfoInstant(itemId)
                if classID == GEM_CLASS then
                    seen[itemId] = true
                    local itemLink = (
                        C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bagId, slotId)
                    ) or nil
                    if not itemLink then
                        -- Data not loaded yet: request it; the row upgrades
                        -- (stat label + tooltip link) when ITEM_DATA_LOAD_RESULT
                        -- lands and the handler repopulates the flyout.
                        pendingGemLoads[itemId] = true
                        if C_Item and C_Item.RequestLoadItemDataByID then
                            C_Item.RequestLoadItemDataByID(itemId)
                        end
                    end
                    gemCache[#gemCache + 1] = {
                        itemID = itemId,
                        link = itemLink,
                        tex = texture,
                    }
                end
            end
        end
    end
    gemsStale = false
end

--------------------------------------------------------------------------------
--  Socket action sequence (event-driven, no timers)
--------------------------------------------------------------------------------

-- Seat the socketing window beside the sheet. It is registered as a "left"
-- panel that outranks the character sheet (pushable 0 against the sheet's 3),
-- so showing it shoves the sheet into the center slot and back again on
-- close: a whole-screen shuffle for every strip action. Ranked equal to the
-- sheet, the panel manager seats it in the center slot next to the sheet
-- instead, for strip actions and manual sessions alike. Panel attributes are
-- the sanctioned insecure-to-secure channel, so this taints nothing.
local socketWindowSeated = false
local function SeatSocketWindow()
    if socketWindowSeated then
        return true
    end
    local frame = _G.ItemSocketingFrame
    if not (frame and _G.SetUIPanelAttribute) then
        return false
    end
    socketWindowSeated = true
    _G.SetUIPanelAttribute(frame, "pushable", 3)
    return true
end

-- End a socketing session the way the player does: hide the window. Its own
-- OnHide handler closes the session, which is the one and only CloseSocketInfo
-- call and SOCKET_INFO_CLOSE for it; calling CloseSocketInfo here as well ends
-- the session a second time, nested inside that handler. The window is never
-- made invisible: when it cannot be hidden (combat) it stays on screen so the
-- player can close it by hand.
local function SafeCloseSession()
    local frame = _G.ItemSocketingFrame
    if frame and frame:IsShown() then
        if not InCombatLockdown() and HideUIPanel then
            HideUIPanel(frame)
        end
    elseif CloseSocketFn then
        -- No window on screen: close the bare session directly.
        CloseSocketFn()
    end
end

local RebuildSockets -- forward declaration
local LayoutSockets
local CloseFlyout -- forward declaration
local OpenFlyout -- forward declaration
local MaybeCloseHoverFlyout -- forward declaration

-- Triggered from a gem-row OnClick (a genuine hardware event).
local function DoSocket(targetSlot, socketIndex, gemItemID)
    if InCombatLockdown() then
        if UIErrorsFrame then
            UIErrorsFrame:AddMessage(_G.ERR_NOT_IN_COMBAT or "Can't do that in combat.", 1, 0.1, 0.1)
        end
        return
    end
    if CHasItem and CHasItem() then
        return
    end -- don't hijack a held item
    if ItemSocketingFrame and ItemSocketingFrame:IsShown() then
        if waiting then
            -- Our previous action is still completing (waiting for its result);
            -- it closes the window itself. Ending it now would cut the
            -- socketing short.
            return
        end
        if ourSession then
            -- Leftover window from our own completed action (its result event
            -- never closed it): end it now so socketing is not silently dead
            -- until the user closes it by hand. Never reopen in the same click --
            -- the old session's SOCKET_INFO_CLOSE would wipe the new pending
            -- mid-flight. The flyout stays open; the next gem click goes through.
            SafeCloseSession()
        end
        return -- manual session: never hijack
    end
    if not SocketInvItem then
        return
    end
    waiting = { slot = targetSlot, socketIndex = socketIndex, gemItemID = gemItemID, acted = false }
    ourSession = true
    SocketInvItem(targetSlot) -- opens the LoD session; we act inside SOCKET_INFO_UPDATE
    CloseFlyout()
end

-- Accept exactly once, and only after the session reports the placed gem as
-- the socket's new gem (the same condition that enables the window's own
-- Apply button); an accept issued before that does nothing. Updates after the
-- accept (the refresh that follows the result) change nothing here.
local function AcceptPlacedGem()
    if not waiting or waiting.accepted then
        return
    end
    local label = GetNewSocketInfoFn and GetNewSocketInfoFn(waiting.socketIndex)
    if label then
        waiting.accepted = true
        if AcceptSocketsFn then
            AcceptSocketsFn()
        end
    end
end

-- Runs inside SOCKET_INFO_UPDATE: places the gem once the session is ready,
-- then accepts once the placement is reported.
local function OnSocketInfoUpdate()
    if not waiting then
        return
    end
    if waiting.acted then
        AcceptPlacedGem()
        return
    end
    local nSock = GetNumSockets and GetNumSockets()
    if not nSock or waiting.socketIndex > nSock then
        -- Session not ready / mismatch: wait for the next update. No timer.
        return
    end
    waiting.acted = true

    local bagId, slotId = FindBagSlotForItem(waiting.gemItemID)
    if not bagId then
        waiting = nil
        SafeCloseSession()
        return
    end

    if C_Container and C_Container.PickupContainerItem then
        C_Container.PickupContainerItem(bagId, slotId)
    end
    if ClickSocketBtn then
        ClickSocketBtn(waiting.socketIndex)
    end
    if CClear then
        CClear()
    end
    -- The placement may already be reported (an update fired inside the
    -- click); otherwise the next SOCKET_INFO_UPDATE accepts it. Confirmation
    -- dialogs (binding, refunds) stay Blizzard's: the window is open for them.
    AcceptPlacedGem()
end

--------------------------------------------------------------------------------
--  Icon painting
--------------------------------------------------------------------------------

local Pix = CludesUI and CludesUI.PanelPP

-- Stat letters on a socket icon ("VC" for a Versatility/Critical Strike gem,
-- largest first), centred along its bottom edge. Opt-in
-- (charSheetSocketPanelStats); "" for an empty socket, a gem with no
-- secondary stat, or a gem whose data has not loaded yet (the load result
-- repaints the strip).
local function PaintStatLetters(button, gemLinkText)
    local textValue = ""
    if gemLinkText and CludesUIDB and CludesUIDB.charSheetSocketPanelStats == true then
        textValue = CludesUI.GetItemStatLetters(gemLinkText)
    end
    local fontStr = button.statLetters
    if textValue == "" then
        if fontStr then
            fontStr:SetText("")
        end
        return
    end
    if not fontStr then
        local font = CludesUI.GetFontPath("blizzardSkin") or STANDARD_TEXT_FONT
        fontStr = button:CreateFontString(nil, "OVERLAY", nil, 7)
        fontStr:SetFont(font, 10, CludesUI.SlugFlag("OUTLINE, SLUG"))
        fontStr:SetPoint("BOTTOM", button, "BOTTOM", 0, 1)
        fontStr:SetTextColor(1, 1, 1, 1)
        button.statLetters = fontStr
    end
    fontStr:SetText(textValue)
end

local function PaintFilledIcon(button, gemLinkText)
    local iconTex = button.icon
    -- Clear atlas / color-texture mode before applying a fileID.
    if iconTex.SetAtlas then
        iconTex:SetAtlas(nil)
    end
    iconTex:SetColorTexture(0, 0, 0, 0)
    iconTex:SetTexture(nil)
    if iconTex.SetVertexColor then
        iconTex:SetVertexColor(1, 1, 1, 1)
    end

    local texture
    if GetInfoInstant then
        texture = select(5, GetInfoInstant(gemLinkText))
    end
    if (not texture) and GetIconByID then
        -- GetItemIconByID wants a numeric itemID, not a link.
        local iid = tonumber(gemLinkText:match("item:(%d+)"))
        if iid then
            texture = GetIconByID(iid)
        end
    end
    iconTex:SetTexture(texture)
    button:SetAlpha(1)

    -- Rarity border (default silver; upgrades async once item data loads).
    local rarity = 2
    local known = false
    if C_Item and C_Item.GetItemInfo then
        local _, _, region = C_Item.GetItemInfo(gemLinkText)
        if region then
            rarity = region
            known = true
        end
    end
    if STOCK then
        -- Blizzard's item-button rule: a quality-tinted frame, none for a
        -- quality the color manager has no color for, and none until the
        -- gem's data has loaded (the load result repaints it).
        local qb = button.qualityBorder
        local color = known
            and ColorManager
            and ColorManager.GetColorDataForBagItemQuality
            and ColorManager.GetColorDataForBagItemQuality(rarity)
        if qb then
            if color then
                qb:SetVertexColor(color.r, color.g, color.b, 1)
                qb:Show()
            else
                qb:Hide()
            end
        end
    elseif Pix and Pix.SetBorderColor then
        Pix.SetBorderColor(button, GemBorderColor(rarity))
    end
end

local function PaintEmptyIcon(button)
    local iconTex = button.icon
    if iconTex.SetAtlas then
        iconTex:SetAtlas(nil)
    end
    iconTex:SetColorTexture(0, 0, 0, 0)
    iconTex:SetTexture(nil)
    if iconTex.SetVertexColor then
        iconTex:SetVertexColor(1, 1, 1, 1)
    end
    iconTex:SetTexture(EMPTY_SOCKET_TEX)
    if STOCK then
        button:SetAlpha(1)
        if button.qualityBorder then
            button.qualityBorder:Hide()
        end
        return
    end
    button:SetAlpha(0.85)
    if Pix and Pix.SetBorderColor then
        Pix.SetBorderColor(button, 1, 1, 1, 0.4)
    end
end

--------------------------------------------------------------------------------
--  Hovered-gem slot glow
--  Hovering a socket icon plays the standard proc glow over the equipment
--  slot button holding that gem. Modern WoW Glow is a FlipBook style: the
--  animation is a C-side AnimationGroup, so no Lua runs while it plays, and
--  the wrapper is created lazily on first hover and fully stopped + hidden
--  on leave / sheet close -- zero cost while not hovering. Taint-safe: the
--  wrapper is OUR frame (parented to CharacterFrame, like the panel); the
--  Blizzard slot button is only ever read (GetID, size, level) and used as
--  an anchor target -- never written to, reparented, or hooked.
--------------------------------------------------------------------------------
local slotHighlight -- our lazy wrapper frame
local slotButtons -- lazy [invSlotID] = Blizzard slot button

local SLOT_BUTTON_NAMES = {
    "Head",
    "Neck",
    "Shoulder",
    "Chest",
    "Waist",
    "Legs",
    "Feet",
    "Wrist",
    "Hands",
    "Finger0",
    "Finger1",
    "Trinket0",
    "Trinket1",
    "Back",
    "MainHand",
    "SecondaryHand",
}

local function SlotButtonFor(slotID)
    if not slotButtons then
        slotButtons = {}
        for _, n in ipairs(SLOT_BUTTON_NAMES) do
            local button = _G["Character" .. n .. "Slot"]
            -- Keyed by the button's own inventory ID, never a hardcoded pairing.
            if button and button.GetID then
                slotButtons[button:GetID()] = button
            end
        end
    end
    return slotButtons[slotID]
end

local function EndSlotGlow()
    if not slotHighlight then
        return
    end
    local G = CludesUI and CludesUI.Glows
    if G and G.StopGlow then
        G.StopGlow(slotHighlight)
    end
    slotHighlight:Hide()
end

local function StartSlotGlow(slotID)
    local G = CludesUI and CludesUI.Glows
    if not (G and G.StartGlow) then
        return
    end
    local slotBtn = SlotButtonFor(slotID)
    if not slotBtn then
        return
    end
    if not slotHighlight then
        slotHighlight = CreateFrame("Frame", nil, CharacterFrame)
    end
    slotHighlight:ClearAllPoints()
    slotHighlight:SetAllPoints(slotBtn)
    slotHighlight:SetFrameStrata(slotBtn:GetFrameStrata())
    slotHighlight:SetFrameLevel(slotBtn:GetFrameLevel() + 5)
    slotHighlight:Show()
    local wid, hgt = slotBtn:GetWidth(), slotBtn:GetHeight()
    if not wid or wid < 1 then
        wid = 37
    end
    if not hgt or hgt < 1 then
        hgt = wid
    end
    -- Style 6 = Modern WoW Glow (proc-loop FlipBook).
    G.StartGlow(slotHighlight, 6, wid, 1, 1, 1, nil, hgt)
end

-- Both bottom strips share the socket icon's size, border and hover treatment.
local function CreatePanelIcon(hostFrame)
    local button = CreateFrame("Button", nil, hostFrame)
    button:SetSize(SIZE, SIZE)

    local iconTex = button:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints(button)
    button.icon = iconTex

    if STOCK then
        -- Blizzard's item-button look: the icon uncropped, a quality-tinted
        -- WhiteIconFrame (painted per socket) and the square ADD highlight.
        local qb = button:CreateTexture(nil, "OVERLAY")
        qb:SetAllPoints(button)
        qb:SetTexture("Interface\\Common\\WhiteIconFrame")
        qb:Hide()
        button.qualityBorder = qb
        local hoverTex = button:CreateTexture(nil, "HIGHLIGHT")
        hoverTex:SetAllPoints(button)
        hoverTex:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        hoverTex:SetBlendMode("ADD")
    else
        -- Standard icon zoom: crop the baked-in dark edge ring off icon art.
        iconTex:SetTexCoord(0.05, 0.95, 0.05, 0.95)

        if Pix and Pix.CreateBorder then
            Pix.CreateBorder(button, 1, 1, 1, 0.4, 1, "OVERLAY", 7)
        end

        -- Hover wash
        local hoverTex = button:CreateTexture(nil, "HIGHLIGHT")
        hoverTex:SetAllPoints(button)
        hoverTex:SetColorTexture(1, 1, 1, 0.1)
    end

    return button
end

local function AcquireIcon(i)
    local button = iconPool[i]
    if button then
        return button
    end
    button = CreatePanelIcon(panelFrame)

    button:SetScript("OnEnter", function(self)
        local record = self.cuiSock
        if not record then
            return
        end
        -- Slot locator glow first: independent of tooltip suppression.
        StartSlotGlow(record.slot)
        -- Hover-to-suggest: an EMPTY socket opens the gem flyout on hover so a
        -- single click on a gem sockets it (click-socket-then-click-gem doubles
        -- the clicks across a many-socket session). Filled sockets keep the
        -- explicit click -- replacing destroys the old gem. Never hijack a
        -- sticky (click-opened) flyout; re-hovering the open icon is a no-op.
        if not record.gemLink and not InCombatLockdown() then
            local open = gemMenu and gemMenu:IsShown()
            if not (open and (activeIcon == self or not menuHoverMode)) then
                OpenFlyout(self, record.slot, record.socketIndex, true)
            end
        end
        if
            CludesUI
            and CludesUI._tooltipSuppressedByMode
            and CludesUI._tooltipSuppressedByMode(GameTooltip)
        then
            return
        end
        if record.gemLink then
            -- Filled socket: real item tooltip (sanctioned item-tooltip surface).
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(record.gemLink)
            GameTooltip:Show()
        else
            -- Empty socket: plain-text hint uses the CUI widget tooltip.
            CludesUI.ShowWidgetTooltip(
                self,
                CludesUI.L(record.emptyName or "Empty Socket")
                    .. CludesUI.L("\nPick a gem from the list to socket it."),
                { anchor = "right" }
            )
        end
    end)
    button:SetScript("OnLeave", function()
        EndSlotGlow()
        MaybeCloseHoverFlyout()
        GameTooltip:Hide()
        CludesUI.HideWidgetTooltip()
    end)
    button:SetScript("OnClick", function(self)
        local record = self.cuiSock
        if not record then
            return
        end
        if InCombatLockdown() then
            if UIErrorsFrame then
                UIErrorsFrame:AddMessage(_G.ERR_NOT_IN_COMBAT or "Can't do that in combat.", 1, 0.1, 0.1)
            end
            return
        end
        -- Toggle: clicking the open icon again closes its flyout. A
        -- hover-opened flyout is pinned sticky instead (the natural read of
        -- clicking the socket whose suggestions are already showing).
        if activeIcon == self and gemMenu and gemMenu:IsShown() then
            if menuHoverMode then
                menuHoverMode = false
                if clickCatcher then
                    clickCatcher:Show()
                end
                return
            end
            CloseFlyout()
            return
        end
        OpenFlyout(self, record.slot, record.socketIndex)
    end)

    iconPool[i] = button
    return button
end

--------------------------------------------------------------------------------
--  Rebuild + layout
--------------------------------------------------------------------------------

-- Best-effort empty-socket type name for an equipped item (cosmetic tooltip line).
local function ItemEmptySocketName(itemLink)
    if not GetItemStatsFn then
        return nil
    end
    local stats = GetItemStatsFn(itemLink)
    if not stats then
        return nil
    end
    local found
    for keyName in pairs(stats) do
        if type(keyName) == "string" and keyName:find("EMPTY_SOCKET") then
            if found then
                return nil
            end -- more than one type -> ambiguous
            found = keyName
        end
    end
    if found then
        return _G[found] or "Empty Socket"
    end
    return nil
end

-- Read the gem itemID for a socket index straight out of the equipped item's
-- link (gem IDs are fields 3-6 of the item string). This needs no item-data
-- cache, unlike C_Item.GetItemGem, which returns nil until the GEM's own item
-- is cached and so painted filled sockets as empty on the first open after
-- login. The extra parens around select() are required: it returns every field
-- from that position onward, and a second value would become tonumber's base.
local function GemIDFromLink(itemLink, position)
    local itemString = itemLink:match("item:([%-%d:]+)")
    if not itemString then
        return nil
    end
    local groupId = tonumber((select(position + 2, strsplit(":", itemString))))
    if groupId and groupId > 0 then
        return groupId
    end
    return nil
end

RebuildSockets = function()
    for i = #sockets, 1, -1 do
        sockets[i] = nil
    end
    for keyName in pairs(relevantItems) do
        relevantItems[keyName] = nil
    end

    if GetItemNumSockets and GetItemGemFn then
        for _, slotId in ipairs(SLOTS) do
            local itemLink = GetInventoryItemLink("player", slotId)
            if itemLink then
                local num = GetItemNumSockets(itemLink) or 0
                if num > 0 then
                    local emptyName = ItemEmptySocketName(itemLink)
                    -- Track the equipped item's itemID so a late data-load for it
                    -- (rarity/stats) can trigger a targeted refresh.
                    if GetInfoInstant then
                        local iid = GetInfoInstant(itemLink)
                        if iid then
                            relevantItems[iid] = true
                        end
                    end
                    for position = 1, num do
                        local _, gemLinkText = GetItemGemFn(itemLink, position)
                        if not gemLinkText then
                            -- Uncached gem: build a bare link from the ID in the
                            -- equipped link (the icon still resolves instantly
                            -- via GetItemInfoInstant) and request the real data;
                            -- the ITEM_DATA_LOAD_RESULT rebuild then upgrades
                            -- the rarity border and tooltip. Requested at most
                            -- once per sheet-open so a failed load cannot chain
                            -- request -> result -> rebuild -> request forever.
                            local groupId = GemIDFromLink(itemLink, position)
                            if groupId then
                                gemLinkText = "item:" .. groupId
                                if
                                    not socketLoadRequested[groupId]
                                    and C_Item
                                    and C_Item.RequestLoadItemDataByID
                                then
                                    socketLoadRequested[groupId] = true
                                    C_Item.RequestLoadItemDataByID(groupId)
                                end
                            end
                        end
                        if gemLinkText and GetInfoInstant then
                            local giid = GetInfoInstant(gemLinkText)
                            if giid then
                                relevantItems[giid] = true
                            end
                        end
                        sockets[#sockets + 1] = {
                            slot = slotId,
                            socketIndex = position,
                            gemLink = gemLinkText,
                            emptyName = emptyName or "Empty Socket",
                        }
                    end
                end
            end
        end
    end

    LayoutSockets()
end

local function ChangeSocketPage(delta)
    local last = math.max(0, math.ceil(#sockets / (MAX_SOCKET_ICONS - 1)) - 1)
    local page = math.max(0, math.min(last, pageIndex + delta))
    if page == pageIndex then
        return
    end
    CloseFlyout()
    EndSlotGlow()
    GameTooltip:Hide()
    CludesUI.HideWidgetTooltip()
    pageIndex = page
    LayoutSockets()
end

local function BuildPageButton(textValue, delta, tipText)
    local button = CreateFrame("Button", nil, panelFrame)
    if STOCK then
        -- The gear flyout's own page arrows; their disabled art shows the ends.
        local art = (delta < 0) and "Interface\\Buttons\\UI-SpellbookIcon-PrevPage"
            or "Interface\\Buttons\\UI-SpellbookIcon-NextPage"
        button:SetSize(PAGE_BUTTON_W, PAGE_BUTTON_W)
        button:SetNormalTexture(art .. "-Up")
        button:SetPushedTexture(art .. "-Down")
        button:SetDisabledTexture(art .. "-Disabled")
        button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    else
        button:SetSize(PAGE_BUTTON_W, SIZE)
        local labelText = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        labelText:SetAllPoints(button)
        labelText:SetText(textValue)
    end
    button:SetScript("OnClick", function()
        ChangeSocketPage(delta)
    end)
    button:SetScript("OnEnter", function(self)
        CludesUI.ShowWidgetTooltip(self, tipText)
    end)
    button:SetScript("OnLeave", function()
        CludesUI.HideWidgetTooltip()
    end)
    return button
end

LayoutSockets = function()
    if not panelFrame then
        return
    end

    panelFrame:ClearAllPoints()
    if seasonPane and seasonPane:IsShown() then
        local gap = STOCK and 12 or PAD -- stock tab art overhangs both plates
        panelFrame:SetPoint(
            STOCK and "TOPRIGHT" or "BOTTOMRIGHT",
            seasonPane,
            STOCK and "TOPLEFT" or "BOTTOMLEFT",
            -gap,
            0
        )
    elseif STOCK then
        panelFrame:SetPoint("TOPRIGHT", CharacterFrame, "BOTTOMRIGHT", -15, 2)
    else
        panelFrame:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMRIGHT", -10, 6)
    end

    -- Season shortcuts only move the strip; its original capacity is unchanged.
    local total = #sockets
    local paged = total > MAX_SOCKET_ICONS
    -- Reserve one icon's width for the arrows. On the CludesUI look that
    -- keeps the strip no wider than the six-socket layout, including on the
    -- last page; the stock plate's larger arrows make its paged plate wider.
    local perPage = paged and (MAX_SOCKET_ICONS - 1) or MAX_SOCKET_ICONS
    local last = math.max(0, math.ceil(total / perPage) - 1)
    pageIndex = math.min(pageIndex, last)
    local first = pageIndex * perPage
    local visible = math.min(perPage, total - first)
    if activeIcon then
        local old = activeIcon.cuiSock
        local keep = false
        for i = 1, visible do
            local record = sockets[first + i]
            if
                activeIcon == iconPool[i]
                and old
                and old.slot == record.slot
                and old.socketIndex == record.socketIndex
            then
                keep = true
                break
            end
        end
        if not keep then
            CloseFlyout()
            EndSlotGlow()
        end
    end
    if paged and not lastPage then
        lastPage = BuildPageButton("<", -1, CludesUI.L("Previous sockets"))
        nextPage = BuildPageButton(">", 1, CludesUI.L("Next sockets"))
        lastPage:SetPoint("LEFT", panelFrame, "LEFT", EDGE_X, ICON_Y)
        nextPage:SetPoint("RIGHT", panelFrame, "RIGHT", -EDGE_X, ICON_Y)
    end
    if lastPage then
        lastPage:SetShown(paged)
        nextPage:SetShown(paged)
        lastPage:SetEnabled(pageIndex > 0)
        nextPage:SetEnabled(pageIndex < last)
        lastPage:SetAlpha((STOCK or pageIndex > 0) and 1 or 0.3)
        nextPage:SetAlpha((STOCK or pageIndex < last) and 1 or 0.3)
    end

    -- Hide all pooled icons first.
    for _, button in ipairs(iconPool) do
        button:Hide()
        button.cuiSock = nil
    end

    -- The durability footer label sits beside this strip on the CludesUI
    -- sheet only (the stock styles move that label to the stats header).
    if total == 0 then
        panelFrame:Hide()
        if not STOCK and CludesUI and CludesUI._updateCharSheetDurability then
            CludesUI._updateCharSheetDurability()
        end
        return
    end

    -- Arrows (one each side when paged) + icons + edge padding. On the
    -- CludesUI look the two arrows fill exactly one icon slot, so this is
    -- the original six-slot width. A plate kept wider by MIN_W centres the row.
    local contentW = 2 * EDGE_X
        + (paged and 2 * (PAGE_BUTTON_W + PAD) or 0)
        + (paged and perPage or visible) * (SIZE + PAD)
        - PAD
    local panelW = math.max(MIN_W, contentW)
    local shift = (panelW - contentW) / 2

    for i = 1, visible do
        local record = sockets[first + i]
        local button = AcquireIcon(i)
        button.cuiSock = record
        if record.gemLink then
            PaintFilledIcon(button, record.gemLink)
        else
            PaintEmptyIcon(button)
        end
        PaintStatLetters(button, record.gemLink)
        button:ClearAllPoints()
        button:SetPoint(
            "LEFT",
            panelFrame,
            "LEFT",
            shift + EDGE_X + (paged and (PAGE_BUTTON_W + PAD) or 0) + (i - 1) * (SIZE + PAD),
            ICON_Y
        )
        button:Show()
    end

    panelFrame:SetWidth(panelW)
    panelFrame:Show()
    if not STOCK and CludesUI and CludesUI._updateCharSheetDurability then
        CludesUI._updateCharSheetDurability()
    end
end

--------------------------------------------------------------------------------
--  Flyout
--------------------------------------------------------------------------------

local function AcquireGemRow(i)
    local line = gemRows[i]
    if line then
        return line
    end

    line = CreateFrame("Button", nil, gemMenu)
    line:SetHeight(ROW_H)

    local iconTex = line:CreateTexture(nil, "ARTWORK")
    iconTex:SetSize(ROW_H - 2, ROW_H - 2)
    iconTex:SetPoint("LEFT", line, "LEFT", 2, 0)
    line.icon = iconTex

    local fontFile = (CludesUI.GetFontPath("blizzardSkin")) or STANDARD_TEXT_FONT
    local labelText = line:CreateFontString(nil, "OVERLAY")
    labelText:SetFont(fontFile, 11, "")
    labelText:SetPoint("LEFT", iconTex, "RIGHT", 5, 0)
    labelText:SetJustifyH("LEFT")
    line.label = labelText

    local total = line:CreateFontString(nil, "OVERLAY")
    total:SetFont(fontFile, 11, "")
    total:SetPoint("RIGHT", line, "RIGHT", -6, 0)
    total:SetJustifyH("RIGHT")
    total:SetTextColor(0.7, 0.7, 0.7)
    line.count = total

    local hoverTex = line:CreateTexture(nil, "HIGHLIGHT")
    hoverTex:SetAllPoints(line)
    if STOCK then
        -- Blizzard's menu row highlight.
        hoverTex:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        hoverTex:SetBlendMode("ADD")
    else
        hoverTex:SetColorTexture(1, 1, 1, 0.1)
    end

    line:SetScript("OnEnter", function(self)
        if not self.gemLink then
            return
        end
        if
            CludesUI
            and CludesUI._tooltipSuppressedByMode
            and CludesUI._tooltipSuppressedByMode(GameTooltip)
        then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.gemLink)
        GameTooltip:Show()
    end)
    line:SetScript("OnLeave", function()
        GameTooltip:Hide()
        MaybeCloseHoverFlyout()
    end)
    line:SetScript("OnClick", function(self)
        if not self.gemItemID then
            return
        end
        DoSocket(gemMenu.targetSlot, gemMenu.targetSocketIndex, self.gemItemID)
    end)

    gemRows[i] = line
    return line
end

local function FillFlyout()
    if gemsStale then
        ScanBagGems()
    end

    for _, line in ipairs(gemRows) do
        line:Hide()
        line.gemItemID = nil
        line.gemLink = nil
    end

    local n = #gemCache
    local isShown = 0
    if n == 0 then
        -- Single greyed "no gems" row.
        local line = AcquireGemRow(1)
        line.icon:SetTexture(nil)
        line.icon:SetColorTexture(0, 0, 0, 0)
        line.label:SetText(CludesUI.L("No gems in bags."))
        line.label:SetTextColor(0.5, 0.5, 0.5)
        line.count:SetText("")
        line.gemItemID = nil
        line.gemLink = nil
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", gemMenu, "TOPLEFT", FLY_PAD, -FLY_PAD)
        line:SetPoint("TOPRIGHT", gemMenu, "TOPRIGHT", -FLY_PAD, -FLY_PAD)
        line:Show()
        isShown = 1
    else
        -- Render at most MAX_FLYOUT_ROWS at a time; the wheel scrolls the window
        -- so a large gem inventory never produces an off-screen, unreachable list.
        local visible = n
        if visible > MAX_FLYOUT_ROWS then
            visible = MAX_FLYOUT_ROWS
        end
        local maxScroll = n - visible
        if flyoutScroll < 0 then
            flyoutScroll = 0
        end
        if flyoutScroll > maxScroll then
            flyoutScroll = maxScroll
        end
        for vis = 1, visible do
            local g = gemCache[flyoutScroll + vis]
            local line = AcquireGemRow(vis)
            line.icon:SetTexture(g.tex)
            line.icon:SetColorTexture(0, 0, 0, 0)
            line.icon:SetTexture(g.tex)
            line.label:SetTextColor(1, 1, 1)
            line.label:SetText(g.link and GetGemStatText(g.link) or "Loading...")
            local c = (GetItemCountFn and GetItemCountFn(g.itemID)) or 1
            line.count:SetText(c .. "x")
            line.gemItemID = g.itemID
            line.gemLink = g.link
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", gemMenu, "TOPLEFT", FLY_PAD, -FLY_PAD - (vis - 1) * ROW_H)
            line:SetPoint("TOPRIGHT", gemMenu, "TOPRIGHT", -FLY_PAD, -FLY_PAD - (vis - 1) * ROW_H)
            line:Show()
            isShown = vis
        end
    end

    gemMenu:SetHeight(FLY_PAD + FLY_BOTTOM + isShown * ROW_H)
end

local function BuildFlyout()
    if gemMenu then
        return
    end

    -- Full-screen click-catcher (our frame), just below the flyout strata.
    clickCatcher = CreateFrame("Button", nil, UIParent)
    clickCatcher:SetAllPoints(UIParent)
    clickCatcher:SetFrameStrata("FULLSCREEN")
    clickCatcher:EnableMouse(true)
    clickCatcher:RegisterForClicks("AnyUp")
    clickCatcher:Hide()
    clickCatcher:SetScript("OnClick", function()
        CloseFlyout()
    end)

    gemMenu = CreateFrame("Frame", "CUI_CharSheet_SocketFlyout", UIParent)
    gemMenu:SetWidth(FLYOUT_W)
    gemMenu:SetHeight(ROW_H + 8)
    gemMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    gemMenu:Hide()

    local backdrop = gemMenu:CreateTexture(nil, "BACKGROUND")
    if STOCK then
        -- Blizzard's dropdown menu background, placed as its menus place it.
        backdrop:SetAtlas("common-dropdown-bg")
        backdrop:SetPoint("TOPLEFT", gemMenu, "TOPLEFT", -10, 3)
        backdrop:SetPoint("BOTTOMRIGHT", gemMenu, "BOTTOMRIGHT", 10, -3)
        backdrop:SetAlpha(0.925)
    else
        backdrop:SetAllPoints(gemMenu)
        backdrop:SetColorTexture(0.06, 0.06, 0.06, 0.95)
        if Pix and Pix.CreateBorder then
            Pix.CreateBorder(gemMenu, 0.2, 0.2, 0.2, 1, 1, "OVERLAY", 1)
        end
    end

    -- Mouse-enabled so the hover-opened flyout can watch its own OnLeave; also
    -- keeps clicks on the menu background from falling through to the sheet.
    gemMenu:EnableMouse(true)
    gemMenu:SetScript("OnLeave", function()
        MaybeCloseHoverFlyout()
    end)

    gemMenu:EnableMouseWheel(true)
    gemMenu:SetScript("OnMouseWheel", function(self, delta)
        if #gemCache <= MAX_FLYOUT_ROWS then
            return
        end
        flyoutScroll = flyoutScroll - delta -- wheel down (-1) advances the window
        FillFlyout()
    end)

    gemMenu:EnableKeyboard(true)
    gemMenu:SetPropagateKeyboardInput(true)
    gemMenu:SetScript("OnKeyDown", function(self, keyName)
        -- SetPropagateKeyboardInput is protected in combat; the flyout is
        -- already being closed by PLAYER_REGEN_DISABLED at that point.
        if InCombatLockdown() then
            return
        end
        if keyName == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            CloseFlyout()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
end

OpenFlyout = function(iconBtn, targetSlot, targetSocketIndex, hoverMode)
    BuildFlyout()
    -- Close any existing flyout first.
    CloseFlyout()

    menuHoverMode = hoverMode and true or false
    gemMenu.targetSlot = targetSlot
    gemMenu.targetSocketIndex = targetSocketIndex
    activeIcon = iconBtn
    flyoutScroll = 0

    FillFlyout()

    -- Anchor below the icon, flip upward if it would clip the screen bottom.
    -- The stock plate extends below its icons: drop past its bottom edge so
    -- the menu does not cover the tab art.
    gemMenu:ClearAllPoints()
    local hgt = gemMenu:GetHeight()
    local btnBottom = iconBtn:GetBottom() or 0
    local drop = 0
    if STOCK and panelFrame then
        drop = btnBottom - (panelFrame:GetBottom() or btnBottom)
    end
    if (btnBottom - drop - hgt - 6) < 0 then
        gemMenu:SetPoint("BOTTOMLEFT", iconBtn, "TOPLEFT", 0, 4)
    else
        gemMenu:SetPoint("TOPLEFT", iconBtn, "BOTTOMLEFT", 0, -4 - drop)
    end

    -- Always start in pass-through state: an ESCAPE-close leaves propagate
    -- false on the hidden frame, which would swallow the first key next open.
    gemMenu:SetPropagateKeyboardInput(true)

    -- Hover mode has no click-catcher: the flyout dismisses itself when the
    -- cursor leaves it, and a stray hover must never eat an unrelated click.
    -- A click on the socket icon pins it sticky, which shows the catcher.
    if not menuHoverMode then
        clickCatcher:Show()
    end
    gemMenu:Show()

    -- Watch for combat while the flyout is open.
    if eventFrame then
        eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    end
end

CloseFlyout = function()
    if gemMenu then
        gemMenu:Hide()
    end
    if clickCatcher then
        clickCatcher:Hide()
    end
    activeIcon = nil
    menuHoverMode = false
    if eventFrame then
        eventFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
    end
end

-- Hover-opened flyouts dismiss when the cursor is over neither the flyout nor
-- the socket icon that opened it. Called from the OnLeave of every surface
-- involved (icon, flyout body, gem rows) -- purely event-driven, no polling.
MaybeCloseHoverFlyout = function()
    if not menuHoverMode then
        return
    end
    if not (gemMenu and gemMenu:IsShown()) then
        return
    end
    -- The margin bridges the 4px anchor gap between icon and flyout so the
    -- cursor can travel across it without this check closing the menu.
    if gemMenu:IsMouseOver(8, -8, -8, 8) then
        return
    end
    if activeIcon and activeIcon:IsMouseOver() then
        return
    end
    CloseFlyout()
end

--------------------------------------------------------------------------------
--  Events (registered only while the panel is shown)
--------------------------------------------------------------------------------

local function EventValid(evt)
    if C_EventUtils and C_EventUtils.IsEventValid then
        return C_EventUtils.IsEventValid(evt)
    end
    return true
end

local SHOWN_EVENTS = {
    "PLAYER_EQUIPMENT_CHANGED",
    "ITEM_CHANGED",
    "SOCKET_INFO_UPDATE",
    "SOCKET_INFO_ACCEPT",
    "SOCKET_INFO_CLOSE",
    "SOCKET_INFO_SUCCESS",
    "SOCKET_INFO_FAILURE",
    "BAG_UPDATE_DELAYED",
    "ITEM_DATA_LOAD_RESULT",
}

local function RegisterShownEvents()
    if shownEvents or not eventFrame then
        return
    end
    shownEvents = true
    for _, ev in ipairs(SHOWN_EVENTS) do
        if EventValid(ev) then
            pcall(eventFrame.RegisterEvent, eventFrame, ev)
        end
    end
end

local function UnregisterShownEvents()
    if not (shownEvents and eventFrame) then
        return
    end
    shownEvents = false
    for _, ev in ipairs(SHOWN_EVENTS) do
        pcall(eventFrame.UnregisterEvent, eventFrame, ev)
    end
    eventFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
end

local function OnEvent(self, evt, arg1)
    if evt == "PLAYER_EQUIPMENT_CHANGED" then
        RebuildSockets()
    elseif evt == "ITEM_CHANGED" then
        -- Socketing modifies the equipped item's link IN PLACE (no re-equip),
        -- so PLAYER_EQUIPMENT_CHANGED stays silent and the accept-time rebuild
        -- still reads the old link; this fires once the link actually changed.
        RebuildSockets()
    elseif evt == "SOCKET_INFO_UPDATE" then
        OnSocketInfoUpdate()
    elseif evt == "SOCKET_INFO_ACCEPT" then
        -- The accept is in flight: the window disables its sockets and the
        -- result follows as SOCKET_INFO_SUCCESS or SOCKET_INFO_FAILURE. The
        -- session stays open until then.
    elseif evt == "SOCKET_INFO_SUCCESS" or evt == "SOCKET_INFO_FAILURE" then
        -- Our action is complete either way: close the window the way the
        -- player would (its OnHide ends the session). A manual session is never
        -- touched. The strip repaints on ITEM_CHANGED / BAG_UPDATE_DELAYED.
        local ours = waiting ~= nil
        waiting = nil
        gemsStale = true
        if ours then
            SafeCloseSession()
        end
    elseif evt == "SOCKET_INFO_CLOSE" then
        waiting = nil
        ourSession = false
        gemsStale = true
        RebuildSockets()
    elseif evt == "BAG_UPDATE_DELAYED" then
        gemsStale = true
        -- The socketed gem just left the bags; refresh the equipped row too,
        -- as the guaranteed fallback if ITEM_CHANGED is ever unavailable.
        RebuildSockets()
        if gemMenu and gemMenu:IsShown() then
            FillFlyout()
        end
    elseif evt == "ITEM_DATA_LOAD_RESULT" then
        -- A bag gem we listed before its data was cached: rescan so its link
        -- and stat label fill in (kept separate from relevantItems, which
        -- RebuildSockets wipes and refills on every pass).
        if arg1 and pendingGemLoads[arg1] then
            pendingGemLoads[arg1] = nil
            gemsStale = true
            if gemMenu and gemMenu:IsShown() then
                FillFlyout()
            end
        end
        -- This event is a global broadcast that fires for EVERY item whose data
        -- finishes loading anywhere in the UI. Only refresh when the loaded item
        -- is one of our tracked equipped/socketed items or their gems, so we do
        -- not run a full 16-slot rebuild on every unrelated bag/tooltip load.
        if panelFrame and panelFrame:IsShown() and (arg1 == nil or relevantItems[arg1]) then
            RebuildSockets()
        end
    elseif evt == "PLAYER_REGEN_DISABLED" then
        CloseFlyout()
    elseif evt == "ADDON_LOADED" then
        -- The socketing UI just loaded: seat its window before its first show.
        if arg1 == "Blizzard_ItemSocketingUI" then
            SeatSocketWindow()
            self:UnregisterEvent("ADDON_LOADED")
        end
    end
end

--------------------------------------------------------------------------------
--  Build + lifecycle
--------------------------------------------------------------------------------

local function CreatePanelFrame(label)
    -- CludesUI look: a bare row of icons in the blank strip along the
    -- sheet's bottom edge, right-aligned, no header or backdrop. Anchoring to
    -- CharacterFrame directly (not a skin frame) means the panel builds fine
    -- on the very first open after login, before the skin's lazy layout runs.
    local panelFrame = CreateFrame("Frame", label, CharacterFrame)
    panelFrame:ClearAllPoints()
    if STOCK then
        -- Stock styles: hung below the sheet's bottom-right corner, mirroring
        -- the bottom tabs at the bottom-left (TOPLEFT +11, +2), in their
        -- inactive tab art placed exactly as PanelTabButtonTemplate places it.
        -- The top 2px tuck under the sheet's metal edge, which draws above.
        panelFrame:SetPoint("TOPRIGHT", CharacterFrame, "BOTTOMRIGHT", -15, 2)
        -- The plate is the tab art stretched 6px taller than its atlas so the
        -- icons get breathing room; the side pieces keep their atlas width, the
        -- centre band stretches (it is uniform across). The row (ICON_Y)
        -- centres on the part below the tuck.
        local linkInfo = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("uiframe-tab-left")
        local rInfo = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("uiframe-tab-right")
        local artH = (linkInfo and linkInfo.height and linkInfo.height > 0) and linkInfo.height or 32
        panelFrame:SetSize(SIZE, artH + 6)
        panelFrame:SetFrameLevel(CharacterFrame:GetFrameLevel() + 4)
        -- The plate hangs outside the sheet, where nothing below catches the
        -- mouse: it takes clicks across its whole painted tab (the art overhangs
        -- 3px left, 7px right) so a near-miss on a socket never reaches the world.
        panelFrame:EnableMouse(true)
        panelFrame:SetHitRectInsets(-3, -7, 0, 0)
        local lW = (linkInfo and linkInfo.width) or 12
        local rW = (rInfo and rInfo.width) or 12
        -- Narrower than this and the end caps overlap (the centre band inverts).
        MIN_W = lW + rW - 10
        local leftX = panelFrame:CreateTexture(nil, "BACKGROUND")
        leftX:SetAtlas("uiframe-tab-left")
        leftX:SetWidth(lW)
        leftX:SetPoint("TOPLEFT", panelFrame, "TOPLEFT", -3, 0)
        leftX:SetPoint("BOTTOMLEFT", panelFrame, "BOTTOMLEFT", -3, 0)
        local right = panelFrame:CreateTexture(nil, "BACKGROUND")
        right:SetAtlas("uiframe-tab-right")
        right:SetWidth(rW)
        right:SetPoint("TOPRIGHT", panelFrame, "TOPRIGHT", 7, 0)
        right:SetPoint("BOTTOMRIGHT", panelFrame, "BOTTOMRIGHT", 7, 0)
        local mid = panelFrame:CreateTexture(nil, "BACKGROUND")
        mid:SetAtlas("_uiframe-tab-center")
        mid:SetPoint("TOPLEFT", leftX, "TOPRIGHT")
        mid:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
    else
        panelFrame:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMRIGHT", -10, 6)
        panelFrame:SetSize(SIZE, SIZE)
        panelFrame:SetFrameLevel(55)
    end

    return panelFrame
end

--------------------------------------------------------------------------------
--  Optional season shortcuts (no frames or events until first enabled show)
--------------------------------------------------------------------------------

local function IsMidnightSeason()
    -- The display season can belong to a different expansion than the client
    -- or the player's account. Unknown season data must not expose the folio.
    return C_SeasonInfo
        and C_SeasonInfo.GetCurrentDisplaySeasonExpansion
        and LE_EXPANSION_MIDNIGHT ~= nil
        and C_SeasonInfo.GetCurrentDisplaySeasonExpansion() == LE_EXPANSION_MIDNIGHT
end

local function FolioUnlocked()
    return C_PlayerInfo
        and C_PlayerInfo.IsExpansionLandingPageUnlockedForPlayer
        and C_PlayerInfo.IsExpansionLandingPageUnlockedForPlayer(LE_EXPANSION_MIDNIGHT)
end

local function OpenSeasonShortcut(self)
    if InCombatLockdown() then
        if UIErrorsFrame then
            UIErrorsFrame:AddMessage(_G.ERR_NOT_IN_COMBAT or "Can't do that in combat.", 1, 0.1, 0.1)
        end
        return
    end
    if self.isFolio then
        if not IsMidnightSeason() or not FolioUnlocked() then
            return
        end
        -- Blizzard's own landing button toggles only once the overlay is applied.
        local page = _G.ExpansionLandingPage
        if page and ToggleExpansionLandingPage and page:IsOverlayApplied() then
            ToggleExpansionLandingPage()
        end
    else
        CludesUI.ToggleGreatVault()
    end
end

local function CreateSeasonIcon(isFolio)
    local button = CreatePanelIcon(seasonPane)
    button.isFolio = isFolio
    if isFolio then
        button.icon:SetAtlas("midnight-landingbutton-up")
    else
        -- Thalassian Token of Merit, shared by Midnight seasons 1 and 2.
        button.icon:SetTexture("Interface\\Icons\\INV_Misc_AzsharaCoin2")
    end
    if STOCK then
        button.qualityBorder:SetVertexColor(0.75, 0.75, 0.75, 1)
        button.qualityBorder:Show()
    elseif Pix and Pix.SetBorderColor then
        Pix.SetBorderColor(button, GemBorderColor(2))
    end
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", OpenSeasonShortcut)
    button:SetScript("OnEnter", function(self)
        self.tooltipShown = true
        local textValue = self.isFolio and CludesUI.L("Omnium Folio") or CludesUI.L("Great Vault")
        if self.isFolio and not FolioUnlocked() then
            textValue = textValue .. "\n" .. CludesUI.L("Unlock the Omnium Folio to use this shortcut.")
        end
        CludesUI.ShowWidgetTooltip(self, textValue, { anchor = "right" })
    end)
    local function HideTooltip(self)
        if self.tooltipShown then
            self.tooltipShown = nil
            CludesUI.HideWidgetTooltip()
        end
    end
    button:SetScript("OnLeave", HideTooltip)
    button:SetScript("OnHide", HideTooltip)
    return button
end

local RefreshSeasonPanel
-- Event frame of the season plate: registered only while the sheet is open with
-- Season Panel on (late season data, and the folio's unlock while it is locked).
local seasonWatcher

local function OnSeasonEvent()
    local wasShown = seasonPane and seasonPane:IsShown() or false
    local oldWidth = wasShown and seasonPane:GetWidth()
    RefreshSeasonPanel()
    local isShown = seasonPane and seasonPane:IsShown() or false
    if isShown ~= wasShown or (isShown and seasonPane:GetWidth() ~= oldWidth) then
        if panelFrame and panelFrame:IsShown() then
            LayoutSockets()
        end
        if not STOCK and CludesUI._updateCharSheetDurability then
            CludesUI._updateCharSheetDurability()
        end
    end
end

local function SeasonWatch(enabled)
    if enabled == (seasonWatcher and seasonWatcher.on or false) then
        return
    end
    if not seasonWatcher then
        seasonWatcher = CreateFrame("Frame")
        seasonWatcher:SetScript("OnEvent", OnSeasonEvent)
    end
    seasonWatcher.on = enabled
    if enabled then
        seasonWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
        seasonWatcher:RegisterEvent("MYTHIC_PLUS_CURRENT_AFFIX_UPDATE")
    else
        seasonWatcher:UnregisterAllEvents()
    end
end

RefreshSeasonPanel = function()
    local saved = CludesUIDB
    local enabled = (
        saved
        and saved.charSheetSeasonPanel ~= false
        and saved.themedCharacterSheet ~= false
        and not CludesUI.BlizzWindowSkinsKilled()
        and PaperDollFrame
        and PaperDollFrame:IsVisible()
    )
            and true
        or false
    SeasonWatch(enabled)
    -- The vault is its own opt-in (Great Vault Shortcut, in the Season Panel
    -- cog); the folio shows in a Midnight season. Nothing to offer = no plate.
    local vault = enabled and saved.charSheetSeasonVault == true
    local gemPage = enabled and IsMidnightSeason() and true or false
    if not (vault or gemPage) then
        if seasonWatcher then
            seasonWatcher:UnregisterEvent("QUEST_LOG_UPDATE")
        end
        if seasonPane then
            seasonPane:Hide()
        end
        return
    end
    if not seasonPane then
        seasonPane = CreatePanelFrame("CUI_CharSheet_SeasonPanel")
    end
    if vault and not seasonPane.vault then
        seasonPane.vault = CreateSeasonIcon(false)
    end
    if gemPage and not seasonPane.folio then
        seasonPane.folio = CreateSeasonIcon(true)
    end
    local unlocked = gemPage and FolioUnlocked() and true or false
    -- The unlock quest is the one live change left once season data is in, and
    -- it never reverts: watch the quest log only while a locked folio shows.
    if gemPage and not unlocked then
        seasonWatcher:RegisterEvent("QUEST_LOG_UPDATE")
    else
        seasonWatcher:UnregisterEvent("QUEST_LOG_UPDATE")
    end
    if
        vault ~= seasonPane.lastVault
        or gemPage ~= seasonPane.lastFolio
        or unlocked ~= seasonPane.lastUnlocked
    then
        seasonPane.lastVault, seasonPane.lastFolio, seasonPane.lastUnlocked = vault, gemPage, unlocked
        local n = (vault and 1 or 0) + (gemPage and 1 or 0)
        local contentW = 2 * EDGE_X + n * SIZE + (n - 1) * PAD
        local panelW = math.max(MIN_W, contentW)
        -- A plate kept wider by MIN_W centres the row, as the socket strip does.
        local posX = (panelW - contentW) / 2 + EDGE_X
        if seasonPane.vault then
            seasonPane.vault:SetShown(vault)
            if vault then
                seasonPane.vault:ClearAllPoints()
                seasonPane.vault:SetPoint("LEFT", seasonPane, "LEFT", posX, ICON_Y)
                posX = posX + SIZE + PAD
            end
        end
        if seasonPane.folio then
            seasonPane.folio:SetShown(gemPage)
            if gemPage then
                seasonPane.folio:ClearAllPoints()
                seasonPane.folio:SetPoint("LEFT", seasonPane, "LEFT", posX, ICON_Y)
                seasonPane.folio:SetAlpha(unlocked and 1 or 0.4)
            end
        end
        seasonPane:SetWidth(panelW)
    end
    seasonPane:Show()
end

local function BuildPanel()
    if built then
        return
    end
    panelFrame = CreatePanelFrame("CUI_CharSheet_SocketPanel")

    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", OnEvent)
    end

    -- The socketing UI loads on demand: seat its window now if it is already
    -- here, otherwise the moment it loads (one event, dropped once it fires).
    if _G.SetUIPanelAttribute and not SeatSocketWindow() then
        eventFrame:RegisterEvent("ADDON_LOADED")
    end

    built = true
end

local function OnPaperDollShow()
    RefreshSeasonPanel()
    if CludesUIDB and (CludesUIDB.themedCharacterSheet == false or CludesUI.BlizzWindowSkinsKilled()) then
        return
    end
    if CludesUIDB and CludesUIDB.charSheetSocketPanel == false then
        if panelFrame then
            panelFrame:Hide()
        end
        if not STOCK and CludesUI._updateCharSheetDurability then
            CludesUI._updateCharSheetDurability()
        end
        return
    end
    if not built then
        BuildPanel()
    end
    if not panelFrame then
        return
    end
    RegisterShownEvents()
    -- Events were unregistered while the sheet was closed, so any bag change
    -- in between (mail, loot, trade) never marked the gem list dirty.
    gemsStale = true
    -- Fresh open: allow one new data-load request per equipped gem, so a
    -- load that failed last time gets retried.
    for keyName in pairs(socketLoadRequested) do
        socketLoadRequested[keyName] = nil
    end
    RebuildSockets()
end

local function OnHideAll()
    -- OnLeave never fires when the sheet hides under the cursor; stop the
    -- slot glow explicitly so its FlipBook anim is not left running hidden.
    EndSlotGlow()
    CloseFlyout()
    UnregisterShownEvents()
    if panelFrame then
        panelFrame:Hide()
    end
    if seasonPane then
        seasonPane:Hide()
    end
    SeasonWatch(false)
end

-- Live apply from the options toggle (no reload).
local function RefreshFromOptions()
    RefreshSeasonPanel()
    if not (PaperDollFrame and PaperDollFrame:IsVisible()) then
        return
    end
    if CludesUIDB and (CludesUIDB.themedCharacterSheet == false or CludesUI.BlizzWindowSkinsKilled()) then
        return
    end
    if CludesUIDB and CludesUIDB.charSheetSocketPanel == false then
        CloseFlyout()
        UnregisterShownEvents()
        if panelFrame then
            panelFrame:Hide()
        end
        if not STOCK and CludesUI._updateCharSheetDurability then
            CludesUI._updateCharSheetDurability()
        end
    else
        if not built then
            BuildPanel()
        end
        if panelFrame then
            RegisterShownEvents()
            RebuildSockets()
        end
    end
end

--------------------------------------------------------------------------------
--  Bootstrap
--------------------------------------------------------------------------------

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
    -- WoW Forever: part of the character sheet makeover, which stands down
    -- there (CludesUIBlizzardSkin_CharacterSheetForever.lua owns the sheet).
    if CludesUI and CludesUI.IS_FOREVER then
        return
    end
    -- The character sheet's Blizz Default (latched for the session): the
    -- strip hangs below Blizzard's sheet as a tab-art plate. Layout values
    -- switch here, before the lazy build reads them.
    STOCK = (mod.CharSheetStock and mod.CharSheetStock()) and true or false
    if STOCK then
        SIZE, PAD, PAGE_BUTTON_W, EDGE_X, ICON_Y = 26, 4, 20, 10, 4
        FLY_PAD, FLY_BOTTOM = 8, 15
    end
    if CludesUI then
        CludesUI._refreshCharSheetSocketPanel = RefreshFromOptions
    end
    if PaperDollFrame then
        PaperDollFrame:HookScript("OnShow", OnPaperDollShow)
        PaperDollFrame:HookScript("OnHide", OnHideAll)
    end
    if CharacterFrame then
        CharacterFrame:HookScript("OnHide", OnHideAll)
    end
end)
