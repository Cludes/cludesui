if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Chat_Skin.lua
--
--  SkinChatFrame: panel, sidebar and its buttons, scroll bar and the rest
--  of one chat frame's chrome.
--  Reads the earlier Chat files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIChat.lua or an earlier CUI_Chat_*.lua file failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local CUI = _G.CludesUI
local CHAT = mod.ECHAT
local Pix = CUI.PP
local min, upper = min, max

local CFD, GetEditBoxHeight, GetFont = Inner.CFD, Inner.GetEditBoxHeight, Inner.GetFont
local GetFrameFontSize, GetInnerBorderColor = Inner.GetFrameFontSize, Inner.GetInnerBorderColor
local GetOutlineFlag, GetTabAreaHeight = Inner.GetOutlineFlag, Inner.GetTabAreaHeight
local HideSidebarIconTooltip = Inner.HideSidebarIconTooltip
local ShowSidebarIconTooltip = Inner.ShowSidebarIconTooltip
local RequestPassthroughSweep, SetAlphaFrames = Inner.RequestPassthroughSweep, Inner.SetAlphaFrames
local OnHyperlinkEnter, OnHyperlinkLeave = Inner.OnHyperlinkEnter, Inner.OnHyperlinkLeave
local ReadActiveChatText, ShowCopyPopup = Inner.ReadActiveChatText, Inner.ShowCopyPopup
local _skinned, SkinEditBox = Inner._skinned, Inner.SkinEditBox
local SetSidebarFadeTarget = Inner.SetSidebarFadeTarget
local SetSidebarLayoutVisible = Inner.SetSidebarLayoutVisible

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._internals, which hands the value to every copy.
local BG_R = Inner.BG_R
Inner.bgRSetters[#Inner.bgRSetters + 1] = function(val) BG_R = val end
local BG_G = Inner.BG_G
Inner.bgGSetters[#Inner.bgGSetters + 1] = function(val) BG_G = val end
local BG_B = Inner.BG_B
Inner.bgBSetters[#Inner.bgBSetters + 1] = function(val) BG_B = val end
local BG_A = Inner.BG_A
Inner.bgASetters[#Inner.bgASetters + 1] = function(val) BG_A = val end
local _sidebarMouseoverLayoutVisible = Inner._sidebarMouseoverLayoutVisible
Inner.sidebarLayoutVisibleSetters[#Inner.sidebarLayoutVisibleSetters + 1] = function(val)
    _sidebarMouseoverLayoutVisible = val
end
local _sidebarFadeFrame
Inner.sidebarFadeFrameSetters[#Inner.sidebarFadeFrameSetters + 1] = function(val) _sidebarFadeFrame = val end

local function SkinChatFrame(castFrame)
    if not castFrame or _skinned[castFrame] then return end
    _skinned[castFrame] = true
    SetAlphaFrames(nil)
    -- A frame skinned while the panel is fully hidden must join the passthrough
    -- set; deferred so it runs after this skin completes.
    RequestPassthroughSweep()
    local name = castFrame:GetName()
    if not name then return end

    -- Undock drop guard: 12.1's StopMovingOrSizing can end a tab-drag undock
    -- with the frame's anchors stripped and never re-baked; the next line of
    -- Blizzard's secure drag-stop then crashes on GetLeft (nil) and loops the
    -- tab's OnUpdate until the script suspends. This post-hook fires between
    -- the strip and that read: re-anchor the point-less frame at the cursor
    -- (the drop spot) so the position save completes cleanly. Same shipped
    -- object-hook shape as the ApplySystemAnchor guard; fires only when a
    -- chat frame stops moving (user drag), self-gates to the broken state.
    hooksecurefunc(castFrame, "StopMovingOrSizing", function(frame)
        if frame.isDocked then return end
        if frame:GetNumPoints() == 0 then
            -- TOPLEFT, matching Blizzard's own undock anchor convention (the
            -- tab drag grabs near the frame's top-left, so a later re-attach
            -- by anchor point lands without a jump; CENTER produced one).
            local issec = _G.issecretvalue
            local curX, curY = GetCursorPosition()
            local es = frame:GetEffectiveScale()
            local wid, hgt = frame:GetWidth() or 430, frame:GetHeight() or 120
            if
                curX
                and curY
                and es
                and es > 0
                and not (issec and (issec(curX) or issec(curY) or issec(wid) or issec(hgt)))
            then
                frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", curX / es - wid / 2, curY / es + hgt / 2)
            else
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        end
    end)

    -- Tab-drag ownership for undockable frames: 12.1's StartMoving capture is
    -- broken for chat frames -- measured: zero-offset init (frame teleports
    -- to the screen corner at drag start), center-snapped to the cursor with
    -- the grab offset discarded, anchor rewritten to CENTER, and the final
    -- bake stripping all points every drag. The grip lane instead: end the
    -- capture the moment it engages and drive the drag with plain per-tick
    -- corner anchors (grab offset preserved, rect readable throughout, so
    -- the panel+text follow natively). Blizzard's drag-stop bookkeeping
    -- (redock, tab position, position save) runs unchanged on our geometry;
    -- its no-op StopMovingOrSizing at release strips nothing.
    local dragTab = _G[name .. "Tab"]
    if dragTab and castFrame ~= _G.ChatFrame1 then
        dragTab:HookScript("OnDragStart", function()
            if castFrame.isDocked then return end
            pcall(function() castFrame:StopMovingOrSizing() end)
            local defaultChat = CFD(castFrame)
            -- Grab reference: the frame's last at-rest rect from the follower
            -- cache -- the capture has already scrambled the live rect by the
            -- time this post-hook runs. Fresh undocks (cache still says
            -- docked) start from the live rect instead: the drop guard just
            -- re-anchored them centered under the cursor, the stock undock
            -- feel. Immediate SetPoint pins the choice before this frame
            -- renders, so re-drags never flash at the guard's spot.
            local l, t
            if not defaultChat._cfWasDocked and defaultChat._cfL and defaultChat._cfT then
                l, t = defaultChat._cfL, defaultChat._cfT
            else
                l, t = castFrame:GetLeft(), castFrame:GetTop()
            end
            local curX, curY = GetCursorPosition()
            local es = castFrame:GetEffectiveScale()
            local issec = _G.issecretvalue
            if not (l and t and curX and curY and es and es > 0) then return end
            if issec and (issec(l) or issec(t) or issec(curX) or issec(curY)) then return end
            pcall(function()
                castFrame:ClearAllPoints()
                castFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
            end)
            defaultChat._tabDragOffX = l - curX / es
            defaultChat._tabDragOffY = t - curY / es
            local texKey = defaultChat._tabDragTicker
            if not texKey then
                texKey = CreateFrame("Frame")
                texKey:Hide()
                texKey:SetScript("OnUpdate", function()
                    if castFrame.isDocked or not IsMouseButtonDown("LeftButton") then
                        texKey:Hide()
                        return
                    end
                    local curX, curY = GetCursorPosition()
                    local es2 = castFrame:GetEffectiveScale()
                    local isec2 = _G.issecretvalue
                    if not (curX and curY and es2 and es2 > 0) then return end
                    if isec2 and (isec2(curX) or isec2(curY)) then return end
                    castFrame:ClearAllPoints()
                    castFrame:SetPoint(
                        "TOPLEFT",
                        UIParent,
                        "BOTTOMLEFT",
                        curX / es2 + defaultChat._tabDragOffX,
                        curY / es2 + defaultChat._tabDragOffY
                    )
                end)
                defaultChat._tabDragTicker = texKey
            end
            texKey:Show()
        end)
    end

    -- NEVER HookScript("OnEvent") on chat frames -- even post-hooks taint the
    -- C-level event dispatcher. Idle reset + pulse detection live on standalone
    -- event frames (sections 5/6 in CUI_Chat_Init.lua).

    -- Unified dark background (covers chat + edit box as one panel). Parented to
    -- UIParent, NEVER to the chat frame: an insecure frame parented to a Blizzard chat
    -- tab/frame is exactly what this module's host design forbids, and the resulting
    -- taint poisons ChatFrame.isLocked tens of seconds away from any callback of ours
    -- -- it comes from structure, not from code we run.
    --
    -- Two things a real parent would have provided are replaced by the state watcher
    -- instead: draw order (strata + level, re-asserted because Blizzard moves chat
    -- frames between levels on dock passes) and visibility (a UIParent child does not
    -- hide with the chat frame, and anchors still resolve against a hidden one).
    -- Deliberately NOT an OnShow hook on the chat frame.
    if not CFD(castFrame).bg then
        local bg = CreateFrame("Frame", nil, UIParent)
        -- NO SetPoint to cf/eb: the panel is placed NUMERICALLY from the chat
        -- frame's rect (PositionChatPanel), like the tab hosts, so nothing of
        -- ours sits in Blizzard's rect chain.
        -- Stock styles: one strata above the chat frame, whose revealed
        -- background would otherwise draw over our text (see
        -- SyncChatFrameState); the chat frame's own strata otherwise.
        bg:SetFrameStrata(mod.ChatStockArt() and "MEDIUM" or castFrame:GetFrameStrata())
        bg:SetFrameLevel(
            mod.ChatStockArt() and (castFrame:GetFrameLevel() + 1) or upper(0, castFrame:GetFrameLevel() - 1)
        )
        bg:SetShown(castFrame:IsShown())

        local bgTex = bg:CreateTexture(nil, "BACKGROUND")
        bgTex._cuiOwned = true
        bgTex:SetAllPoints()
        -- Unpainted under the stock styles (Blizzard's own background shows;
        -- WoW Forever fills its own framed boxes).
        bgTex:SetColorTexture(BG_R, BG_G, BG_B, mod.ChatStock() and 0 or BG_A)

        -- NO cf:HookScript("OnShow") to mirror visibility: FCF_OpenTemporary- Window
        -- shows the pooled frame partway through (via SetShown), so on any frame
        -- skinned while hidden (pooled temp window between conversations, or restored
        -- by reload with a whisper open) that closure would run INSIDE the open and
        -- taint the rest of it. The state watcher carries shown-state instead.
        CFD(castFrame).bg = bg
        -- WoW Forever: the bronze message and input frames, on our panel.
        if mod.ChatForever() then CHAT.FV_BuildPanel(castFrame, bg, GetEditBoxHeight()) end
    end

    -- Sidebar: icon panel beside the main chat frame. Parented to UIParent so it
    -- stays visible regardless of the active tab.
    if name == "ChatFrame1" and not CFD(castFrame).sidebar then
        -- Stock styles dress the sidebar as the stock chat button column
        -- (CludesUIChat_SidebarStock.lua); ECHAT.SB_KIT is nil otherwise.
        if CHAT.SB_Latch then CHAT.SB_Latch() end
        local sideBar = CreateFrame("Frame", nil, UIParent)
        sideBar:SetWidth(
            min(
                100,
                upper(
                    30,
                    CHAT.DB().sidebarWidth or (CHAT.SidebarWidthDefault and CHAT.SidebarWidthDefault() or 40)
                )
            )
        )
        sideBar:SetPoint("TOPRIGHT", CFD(castFrame).bg, "TOPLEFT", 0, 0)
        sideBar:SetPoint("BOTTOMRIGHT", CFD(castFrame).bg, "BOTTOMLEFT", 0, 0)
        -- Stock column: MEDIUM, as Blizzard's own column buttons and the stock
        -- panel (the chat frame's toplevel LOW art would draw over it). WoW
        -- Forever strips that art and keeps the chat frame's strata, as the
        -- CludesUI look does: there Blizzard's chat menu button, seated
        -- over our Chat Menu icon, takes no click while the column sits a
        -- strata above the chat frame (field-measured).
        sideBar:SetFrameStrata(
            (CHAT.SB_KIT and mod.ChatStockArt()) and "MEDIUM" or castFrame:GetFrameStrata()
        )
        sideBar:SetFrameLevel(castFrame:GetFrameLevel() + 1)

        local sbBg = sideBar:CreateTexture(nil, "BACKGROUND")
        sbBg:SetAllPoints()
        sbBg:SetColorTexture(BG_R, BG_G, BG_B, mod.ChatStock() and 0 or BG_A)
        if CHAT.SB_KIT and CHAT.SB_KIT.backdrop then CHAT.SB_BuildBackdrop(sideBar, CFD(castFrame)) end

        sideBar:EnableMouse(true)
        sideBar:SetScript("OnEnter", function()
            local conf = CHAT.DB()
            if conf.sidebarVisibility == "mouseover" then
                -- Fade target MUST be set before the layout pass: the icon
                -- shown-state in ApplySidebarIcons reads it to decide whether
                -- the faded-out cutoff still applies.
                SetSidebarFadeTarget(1)
                if not _sidebarMouseoverLayoutVisible then
                    SetSidebarLayoutVisible(true)
                    if CHAT.ApplyTabPadding then
                        CHAT.ApplyTabPadding()
                    elseif CHAT.ApplyExtendedBackground then
                        CHAT.ApplyExtendedBackground()
                    end
                end
                if _sidebarFadeFrame then _sidebarFadeFrame:Show() end
            end
        end)
        sideBar:SetScript("OnLeave", function()
            local conf = CHAT.DB()
            if conf.sidebarVisibility == "mouseover" then
                C_Timer.After(0, function()
                    local over = sideBar:IsMouseOver()
                    if issecretvalue and issecretvalue(over) then over = false end
                    if not over then
                        SetSidebarFadeTarget(0)
                        if _sidebarFadeFrame then _sidebarFadeFrame:Show() end
                    end
                end)
            end
        end)

        local onePx = (Pix and Pix.mult) or 1
        local sbDiv = sideBar:CreateTexture(nil, "OVERLAY", nil, 7)
        sbDiv._cuiOwned = true
        sbDiv:SetWidth(onePx)
        sbDiv:SetColorTexture(GetInnerBorderColor(CHAT.DB()))
        sbDiv:SetPoint("TOPRIGHT", sideBar, "TOPRIGHT", 0, 0)
        sbDiv:SetPoint("BOTTOMRIGHT", sideBar, "BOTTOMRIGHT", 0, 0)
        if Pix and Pix.DisablePixelSnap then Pix.DisablePixelSnap(sbDiv) end
        if CHAT.BordersHidden(CHAT.DB()) then sbDiv:Hide() end
        CFD(castFrame).sidebarDiv = sbDiv

        local MEDIA = "Interface\\AddOns\\CludesUIChat\\Media\\"
        local ICON_SIZE = 22
        local ICON_SPACING = 10
        local ICON_ALPHA = 0.4
        local ICON_HOVER_ALPHA = 0.9

        local function MakeSidebarIcon(hostFrame, texPath, anchorTo, anchorPoint, yOff, key)
            local button = CreateFrame("Button", nil, hostFrame)
            button:SetSize(ICON_SIZE, ICON_SIZE)
            if anchorTo then
                button:SetPoint("TOP", anchorTo, "BOTTOM", 0, -ICON_SPACING)
            else
                button:SetPoint(
                    anchorPoint or "TOP",
                    hostFrame,
                    anchorPoint or "TOP",
                    0,
                    yOff or -ICON_SPACING
                )
            end
            local iconTex = button:CreateTexture(nil, "ARTWORK")
            -- Stock styles: the kit dresses the button (no CludesUI tint,
            -- alpha or hover hooks).
            if CHAT.SB_KIT and key then
                button._icon = iconTex
                if key == "scroll" then
                    CHAT.SB_DressScroll(button, "sidebar")
                else
                    CHAT.SB_Dress(button, key)
                end
                return button
            end
            iconTex:SetAllPoints()
            iconTex:SetTexture(texPath)
            iconTex:SetDesaturated(true)
            iconTex:SetVertexColor(1, 1, 1, ICON_ALPHA)
            button:HookScript("OnEnter", function() iconTex:SetVertexColor(1, 1, 1, ICON_HOVER_ALPHA) end)
            button:HookScript("OnLeave", function() iconTex:SetVertexColor(1, 1, 1, ICON_ALPHA) end)
            button._icon = iconTex
            return button
        end

        -- Visibility + ordering config is read once, at creation time.
        local icfg = CHAT.DB()
        local showFriends = icfg.showFriends ~= false
        local showGuild = icfg.showGuild ~= false
        local showDurability = icfg.showDurability ~= false

        -- Extended background grows the sidebar upward by the tab-strip height,
        -- so chain-anchored icons shift up the same amount to keep the top gap.
        -- Skipped under free-move: those icons are user-positioned, not chained.
        local iconTopShift = (CHAT.ExtendBgBehindTabs(icfg) and not icfg.freeMoveIcons) and GetTabAreaHeight()
            or 0

        -- Chain icons are created in the saved order (drag-to-reorder in the
        -- options dropdown; a new order takes effect on the next reload).
        local anchor = nil
        local friendsButton, friendsOnline, durabilityButton, durability, copyBtn, portalBtn, voiceBtn, settingsButton
        local guildButton, guildOnline, chatMenuBtn

        local function ChainAnchor(button)
            button:ClearAllPoints()
            if anchor then
                button:SetPoint("TOP", anchor, "BOTTOM", 0, -ICON_SPACING)
            else
                button:SetPoint("TOP", sideBar, "TOP", 0, -ICON_SPACING + iconTopShift)
            end
        end

        local function CreateFriendsIcon()
            friendsButton = MakeSidebarIcon(sideBar, MEDIA .. "chat_friends.png", nil, nil, nil, "friends")
            friendsButton:SetSize(26, 26)
            ChainAnchor(friendsButton)

            if CHAT.SB_KIT then
                friendsOnline = CHAT.SB_MakeCount(friendsButton, sideBar, "friends")
            else
                friendsOnline = sideBar:CreateFontString(nil, "OVERLAY")
                friendsOnline:SetFont(GetFont(), 9, "")
                friendsOnline:SetTextColor(1, 1, 1, 0.5)
                friendsOnline:SetPoint("TOP", friendsButton, "BOTTOM", 0, 7)
            end
            friendsOnline:SetText("0")

            friendsButton:HookScript("OnEnter", function(self)
                if not CHAT.SB_KIT then friendsOnline:SetTextColor(1, 1, 1, 0.9) end
                if not self._freeMoveJustDragged then ShowSidebarIconTooltip(self, "Friends") end
            end)
            friendsButton:HookScript("OnLeave", function(self)
                if not CHAT.SB_KIT then friendsOnline:SetTextColor(1, 1, 1, 0.5) end
                HideSidebarIconTooltip(self)
            end)

            local fcLast
            local function UpdateFriendsCount()
                if InCombatLockdown() then
                    mod.CombatQueue.Defer(UpdateFriendsCount, UpdateFriendsCount)
                    return
                end
                local _, numOnline = BNGetNumFriends()
                local wowOnline = C_FriendList.GetNumOnlineFriends() or 0
                local sum = numOnline + wowOnline
                if sum ~= fcLast then
                    fcLast = sum
                    friendsOnline:SetText(sum)
                end
            end

            local friendEvents = CreateFrame("Frame")
            friendEvents:RegisterEvent("BN_FRIEND_LIST_SIZE_CHANGED")
            friendEvents:RegisterEvent("BN_FRIEND_ACCOUNT_ONLINE")
            friendEvents:RegisterEvent("BN_FRIEND_ACCOUNT_OFFLINE")
            friendEvents:RegisterEvent("FRIENDLIST_UPDATE")
            friendEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
            friendEvents:RegisterEvent("BN_CONNECTED")
            friendEvents:RegisterEvent("BN_DISCONNECTED")
            -- Recount inline on the exact edges -- the narrow account
            -- online/offline pair (the same field-proven set the DataBars
            -- micromenu count uses), NOT the BN_FRIEND_INFO_CHANGED presence
            -- firehose, so nothing fires between real login/logout edges.
            -- Two cached count reads plus one compare, no timers, and the
            -- label only rewrites when the number changed. In combat nothing
            -- recounts at all -- the count defers itself once to the combat
            -- queue and settles on the regen edge.
            friendEvents:SetScript("OnEvent", UpdateFriendsCount)

            CFD(castFrame).friendsCount = friendsOnline
            -- A count inside its button (the stock QuickJoin plate) is not a
            -- tail: the chain hangs off the button.
            anchor = friendsButton._sbTailInside and friendsButton or friendsOnline
        end

        local function CreateGuildIcon()
            guildButton = MakeSidebarIcon(sideBar, MEDIA .. "chat_guild.png", nil, nil, nil, "guild")
            guildButton:SetSize(26, 26)
            ChainAnchor(guildButton)

            if CHAT.SB_KIT then
                guildOnline = CHAT.SB_MakeCount(guildButton, sideBar, "guild")
            else
                guildOnline = sideBar:CreateFontString(nil, "OVERLAY")
                guildOnline:SetFont(GetFont(), 9, "")
                guildOnline:SetTextColor(1, 1, 1, 0.5)
                guildOnline:SetPoint("TOP", guildButton, "BOTTOM", 0, 7)
            end
            guildOnline:SetText("0")

            guildButton:HookScript("OnEnter", function(self)
                if not CHAT.SB_KIT then guildOnline:SetTextColor(1, 1, 1, 0.9) end
                if not self._freeMoveJustDragged then ShowSidebarIconTooltip(self, "Guild") end
            end)
            guildButton:HookScript("OnLeave", function(self)
                if not CHAT.SB_KIT then guildOnline:SetTextColor(1, 1, 1, 0.5) end
                HideSidebarIconTooltip(self)
            end)

            -- Online guildmate count (GetNumGuildMembers 2nd return). The roster
            -- request MUST stay throttled: GuildRoster() itself fires
            -- GUILD_ROSTER_UPDATE, which re-enters this and loops.
            local lastRoster = 0
            local function UpdateGuildCount()
                if not IsInGuild() then
                    guildOnline:SetText(0)
                    return
                end
                local nowTime = GetTime()
                if not InCombatLockdown() and (nowTime - lastRoster) >= 15 then
                    lastRoster = nowTime
                    C_GuildInfo.GuildRoster()
                end
                local _, online = GetNumGuildMembers()
                guildOnline:SetText(online)
            end

            local gcEvents = CreateFrame("Frame")
            gcEvents:RegisterEvent("GUILD_ROSTER_UPDATE")
            gcEvents:RegisterEvent("PLAYER_GUILD_UPDATE")
            gcEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
            gcEvents:SetScript("OnEvent", UpdateGuildCount)

            CFD(castFrame).guildCount = guildOnline
            anchor = guildOnline
        end

        local function CreateDurabilityIcon()
            durabilityButton =
                MakeSidebarIcon(sideBar, MEDIA .. "chat_durability.png", nil, nil, nil, "durability")
            ChainAnchor(durabilityButton)

            if CHAT.SB_KIT then
                durability = CHAT.SB_MakeCount(durabilityButton, sideBar, "durability")
            else
                durability = sideBar:CreateFontString(nil, "OVERLAY")
                durability:SetFont(GetFont(), 9, "")
                durability:SetTextColor(1, 1, 1, 0.5)
                durability:SetPoint("TOP", durabilityButton, "BOTTOM", 0, 0)
            end
            durability:SetText("100%")

            durabilityButton:HookScript("OnEnter", function(self)
                if not CHAT.SB_KIT then durability:SetTextColor(1, 1, 1, 0.9) end
                if not self._freeMoveJustDragged then ShowSidebarIconTooltip(self, "Equipment Durability") end
            end)
            durabilityButton:HookScript("OnLeave", function(self)
                if not CHAT.SB_KIT then durability:SetTextColor(1, 1, 1, 0.5) end
                HideSidebarIconTooltip(self)
            end)

            local lastDurText
            local function UpdateDurability()
                local lowest = 100
                for slot = 1, 18 do
                    local current, mx = GetInventoryItemDurability(slot)
                    if current and mx and mx > 0 then
                        local pct = (current / mx) * 100
                        if pct < lowest then lowest = pct end
                    end
                end
                local txt = math.floor(lowest) .. "%"
                if txt ~= lastDurText then
                    lastDurText = txt
                    durability:SetText(txt)
                end
                -- Stock styles: the doll takes Blizzard's alert tint.
                if CHAT.SB_KIT then CHAT.SB_DurabilityAlert(durabilityButton) end
            end

            -- Durability + alert events land together per damaged slot; one
            -- recount after the frame settles. Self-repair items fire only the
            -- alert event.
            local durPending = false
            local function FlushDurability()
                durPending = false
                UpdateDurability()
            end
            local durEvents = CreateFrame("Frame")
            durEvents:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
            durEvents:RegisterEvent("UPDATE_INVENTORY_ALERTS")
            durEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
            durEvents:SetScript("OnEvent", function()
                if durPending then return end
                durPending = true
                C_Timer.After(0, FlushDurability)
            end)

            CFD(castFrame).durabilityPct = durability
            -- A percent inside its button is not a tail (as friends above).
            anchor = durabilityButton._sbTailInside and durabilityButton or durability
        end

        -- Friends/Guild/Durability have bespoke creators (count or percent text
        -- plus events); the rest are plain sidebar icons.
        local SPECIAL_CREATORS = {
            showFriends = { show = showFriends, create = CreateFriendsIcon },
            showGuild = { show = showGuild, create = CreateGuildIcon },
            showDurability = { show = showDurability, create = CreateDurabilityIcon },
        }
        local MIDDLE_DEFS = {
            showCopy = { tex = "chat_copy.png", key = "copy" },
            showPortals = { tex = "chat_portal.png", size = 26, key = "portals" },
            showVoice = { tex = "chat_voice.png", key = "voice" },
            showChatMenu = { path = CHAT.CHAT_MENU_GLYPH, key = "chatmenu" },
            showSettings = { tex = "chat_settings.png", key = "settings" },
        }
        local middleBtns = {}
        local chainOrder = CHAT.ResolveSidebarIconOrder()
        -- Classic WoW UI dresses Chat Menu in Blizzard's chat bubble, which
        -- Settings wears otherwise (ECHAT.SB_Dress reads this before either
        -- button is made).
        CHAT.SB_ChatMenuOn = icfg.showChatMenu ~= false and tContains(chainOrder, "showChatMenu") or nil
        for _, key in ipairs(chainOrder) do
            local special = SPECIAL_CREATORS[key]
            if special then
                if special.show then special.create() end
            else
                local def = MIDDLE_DEFS[key]
                if def and icfg[key] ~= false then
                    local button =
                        MakeSidebarIcon(sideBar, def.path or (MEDIA .. def.tex), nil, nil, nil, def.key)
                    if def.size then button:SetSize(def.size, def.size) end
                    ChainAnchor(button)
                    anchor = button
                    middleBtns[key] = button
                end
            end
        end
        copyBtn = middleBtns["showCopy"]
        portalBtn = middleBtns["showPortals"]
        voiceBtn = middleBtns["showVoice"]
        chatMenuBtn = middleBtns["showChatMenu"]
        settingsButton = middleBtns["showSettings"]

        -- Scroll is pinned to the sidebar bottom, outside the chain.
        local scrollButton = MakeSidebarIcon(sideBar, MEDIA .. "chat_scroll2.png", nil, nil, nil, "scroll")
        scrollButton:SetSize(22, 22)
        scrollButton:ClearAllPoints()
        -- Stock column: its bottom-button slot, flush with the column's foot.
        scrollButton:SetPoint("BOTTOM", sideBar, "BOTTOM", 0, CHAT.SB_KIT and 0 or ICON_SPACING)

        local function AddIconTooltip(button, labelText)
            button:HookScript("OnEnter", function(self)
                if not self._freeMoveJustDragged then ShowSidebarIconTooltip(self, labelText) end
            end)
            button:HookScript("OnLeave", function(self) HideSidebarIconTooltip(self) end)
        end
        if copyBtn then AddIconTooltip(copyBtn, "Copy Chat") end
        if voiceBtn then AddIconTooltip(voiceBtn, "Voice/Channels") end
        if settingsButton then AddIconTooltip(settingsButton, "Settings") end
        AddIconTooltip(scrollButton, "Scroll to Bottom")
        -- No click of ours: Blizzard's own button takes it (ECHAT.AttachChatMenu).
        if chatMenuBtn then
            AddIconTooltip(chatMenuBtn, "Chat Menu")
            CHAT.AttachChatMenu(chatMenuBtn)
        end

        -- Scroll to bottom: acts on OUR message frame for the selected window.
        scrollButton:SetScript("OnClick", function()
            local selected = GENERAL_CHAT_DOCK
                and FCFDock_GetSelectedWindow
                and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
            if CHAT.EngineScrollToBottom then CHAT.EngineScrollToBottom(selected or ChatFrame1) end
        end)

        -- Copy chat history from the active tab (reads directly from the frame)
        if copyBtn then
            copyBtn:SetScript("OnClick", function()
                local fullText = ReadActiveChatText()
                if fullText == "" then fullText = "(No chat history)" end
                ShowCopyPopup(fullText)
            end)
        end

        if friendsButton then
            friendsButton:SetScript("OnClick", function()
                if InCombatLockdown() then
                    UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1.0, 0.3, 0.3, 1.0)
                    return
                end
                ToggleFriendsFrame()
            end)
        end

        if guildButton then
            guildButton:SetScript("OnClick", function()
                if InCombatLockdown() then
                    UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1.0, 0.3, 0.3, 1.0)
                    return
                end
                ToggleGuildFrame()
            end)
        end

        if portalBtn then
            portalBtn:SetScript("OnClick", function(self)
                if InCombatLockdown() then return end
                CHAT.TogglePortalFlyout(self)
            end)
            AddIconTooltip(portalBtn, "M+ Portals")
        end

        if voiceBtn then
            voiceBtn:SetScript("OnClick", function()
                if InCombatLockdown() then return end
                ToggleChannelFrame()
            end)
            -- Blizzard Style: the headset while a voice channel is active.
            if CHAT.SB_KIT and CHAT.SB_KIT.voiceState then CHAT.SB_WatchVoice(voiceBtn) end
        end

        if settingsButton then
            settingsButton:SetScript("OnClick", function()
                if InCombatLockdown() then return end
                local mf = CUI._mainFrame
                -- Folded to the mini window: fall through to ShowModule, which unfolds it.
                if
                    mf
                    and mf:IsShown()
                    and not CUI._panelCollapsed
                    and CUI:GetActiveModule() == "CludesUIChat"
                then
                    mf:Hide()
                else
                    CUI:ShowModule("CludesUIChat")
                    -- Scroll the sidebar to the bottom so Chat is visible.
                    C_Timer.After(0, function()
                        local scrollFrame = CUI._addonScrollFrame
                        if scrollFrame then
                            local upper = scrollFrame:GetVerticalScrollRange() or 0
                            scrollFrame:SetVerticalScroll(upper)
                            -- Poke the scroll child so OnScrollRangeChanged fires
                            -- and the thumb updates.
                            local sc = scrollFrame:GetScrollChild()
                            if sc then
                                local hgt = sc:GetHeight()
                                sc:SetHeight(hgt + 0.01)
                                sc:SetHeight(hgt)
                            end
                        end
                    end)
                end
            end)
        end

        local sideBarData = CFD(castFrame)
        sideBarData.friendsBtn = friendsButton
        sideBarData.guildBtn = guildButton
        sideBarData.durabilityBtn = durabilityButton
        sideBarData.copyBtn = copyBtn
        sideBarData.portalBtn = portalBtn
        sideBarData.voiceBtn = voiceBtn
        sideBarData.chatMenuBtn = chatMenuBtn
        sideBarData.settingsBtn = settingsButton
        sideBarData.scrollBtn = scrollButton
        -- Order snapshot for ApplySidebarIcons: live visibility toggles keep this
        -- session's layout; a changed saved order applies on reload.
        sideBarData._iconChainOrder = chainOrder
        -- Stock kit: sizes, pads and free-move heights stamped before the
        -- login chain lays the column out and captures free-move naturals.
        if CHAT.SB_KIT then
            CHAT.SB_ApplyScale(sideBarData, CHAT.DB().sidebarIconScale or 1, true)
            if CHAT.SB_FlashSync then CHAT.SB_FlashSync() end
        end

        CFD(castFrame).sidebar = sideBar
    end

    -- Horizontal divider above the input field. The bg guard is load-bearing: a
    -- frame can reach here without a panel, and an unguarded index throws and
    -- aborts the rest of SkinChatFrame.
    if not CFD(castFrame).inputDiv and CFD(castFrame).bg then
        local onePx = (Pix and Pix.mult) or 1
        local div = CFD(castFrame).bg:CreateTexture(nil, "OVERLAY", nil, 7)
        div._cuiOwned = true
        div:SetHeight(onePx)
        div:SetColorTexture(GetInnerBorderColor(CHAT.DB()))
        div:SetPoint("BOTTOMLEFT", castFrame, "BOTTOMLEFT", -10, -8)
        div:SetPoint("BOTTOMRIGHT", castFrame, "BOTTOMRIGHT", 10, -8)
        if Pix and Pix.DisablePixelSnap then Pix.DisablePixelSnap(div) end
        -- Stock styles: no divider (Blizzard's own input box is below the frame).
        if mod.ChatStock() then div:Hide() end
        CFD(castFrame).inputDiv = div
    end

    -- Font/shadow/fade, one-time at login. The Blizzard frame still gets the
    -- font: its invisible text layout must stay congruent with OUR visible
    -- copy so its hyperlink hit-zones sit under the same characters, and the
    -- hosted combat log renders through it.
    local cfId = castFrame:GetID()
    do
        -- Family over raw file (CJK members) -- same object the engine view
        -- uses, keeping both layouts congruent.
        local fam = CHAT.EngineFontFamily
            and CHAT.EngineFontFamily(cfId, GetFont(), GetFrameFontSize(cfId), GetOutlineFlag())
        if fam then
            castFrame:SetFontObject(fam)
        else
            castFrame:SetFont(GetFont(), GetFrameFontSize(cfId), GetOutlineFlag())
        end
    end
    if castFrame.SetShadowOffset then castFrame:SetShadowOffset(1, -1) end
    if castFrame.SetShadowColor then castFrame:SetShadowColor(0, 0, 0, 0.8) end
    castFrame:SetFading(false)
    -- Must match win.smf's SetIndentedWordWrap(true) (Engine.lua CreateWindowSMF):
    -- Blizzard's own hyperlink hit-zone positions for this frame are computed
    -- against ITS OWN indent setting, not just its text. Leaving this at the
    -- default (false) here while our visible copy indents wrapped lines desyncs
    -- every hyperlink hit-zone from the visible glyphs on that line -- root
    -- cause of player-name/channel-tag links (e.g. whispers, party chat)
    -- clicking several characters off from where the name is drawn.
    castFrame:SetIndentedWordWrap(true)

    -- 3. Hyperlink handlers: hover tooltip only. Blizzard's invisible text
    --    layer owns hyperlink hit-testing (its clicks run SetItemRef from
    --    ITS secure scripts; the global SetItemRef hook catches our URL
    --    links) and these hooks fire on hover. The engine's buffer
    --    write-back keeps that layer's zones laid out under our rendered
    --    text even for width-transformed lines.
    if not CFD(castFrame).hyperlinkHooked then
        CFD(castFrame).hyperlinkHooked = true
        castFrame:HookScript("OnHyperlinkEnter", function(...) OnHyperlinkEnter(...) end)
        castFrame:HookScript("OnHyperlinkLeave", function(...) OnHyperlinkLeave(...) end)
    end

    -- 4. Edit box
    SkinEditBox(castFrame)

    -- 5. Tabs are the owned strip's business now (CludesUIChat_Tabs.lua);
    --    nothing of Blizzard's tab is skinned or touched here.

    -- 6. Hide Blizzard's button frame -- ALPHA, NEVER SetParent. FCF_DockFrame
    -- calls FCF_SetButtonSide (ClearAllPoints+SetPoint on chatFrame.
    -- buttonFrame against chatFrame.Background) then FCF_SetLocked, whose
    -- `chatFrame.isLocked = ...` write is the field measured tainted. Parenting
    -- the button frame to ours would put Blizzard manipulating an insecure-owned frame
    -- mid-dock, tainting the rest of that dock -- that one field feeds both reported
    -- error classes: FCF_Tab_SetupMenu (tab menu) and FCF_UpdateResizeButton
    -- (temp-window open) both read it. On an undocked window FCF_FadeIn/OutChatFrame
    -- animate this frame's alpha every frame (to 1 on hover, 0.2 after), which no
    -- alpha assert outpaces, and a SetAlpha hook would run inside those fades and
    -- the dock pass. Blizzard never re-textures the frame or its minimize button, so
    -- their art is emptied once instead: the fades then have nothing to draw.
    local btnFrame = _G[name .. "ButtonFrame"]
    if btnFrame then
        btnFrame:SetAlpha(0)
        btnFrame:EnableMouse(false)
        -- Empty the border/background textures so btnFrame's own hover/undock
        -- alpha fades (0.2-1, never fully off) have nothing left to draw. The
        -- minimize button is left alone: a separate child object, Blizzard
        -- fades it in with btnFrame's alpha on hover the same as any other
        -- chat window, and its own alpha/mouse state were never touched here.
        local regions = { btnFrame:GetRegions() }
        for index = 1, #regions do
            local regionFrame = regions[index]
            if regionFrame:IsObjectType("Texture") then regionFrame:SetTexture("") end
        end
    end

    -- Restyle Blizzard's resize button to align with our bg (undocked-capable
    -- frames only; ChatFrame1 gets OUR grip below -- Blizzard never shows the
    -- main window's own button, and ApplyLockChatSize keeps it dead).
    local resizeButton = castFrame ~= _G.ChatFrame1 and _G[name .. "ResizeButton"] or nil
    if resizeButton then
        -- DEFERRED for the same reason panel placement is (PositionChatPanel):
        -- this runs from the skin pass, which fires while a temp whisper
        -- window is opening, and re-anchoring this button resolves geometry
        -- against the chat frame inside Blizzard's dock pass, tainting it.
        C_Timer.After(0, function()
            -- Stock styles keep Blizzard's own size grabber (art, anchor and
            -- alpha); only the follower arming below applies. WoW Forever
            -- strips Blizzard's frame art, so it takes ours.
            local stock = mod.ChatStockArt()
            if not stock then
                resizeButton:SetSize(18, 18)
                resizeButton:ClearAllPoints()
                -- Anchored to the CHAT FRAME, NEVER our panel: Blizzard anchors the chat
                -- frame's own ScrollBar to this button (FCF_UpdateScrollbarAnchors), so
                -- pointing it at our panel pulls an addon frame into Blizzard's chat layout
                -- chain (an anchor cycle) and Edit Mode can no longer commit a chat move --
                -- the drag releases unanchored and UpdateSystemAnchorInfo writes nil,
                -- leaving chat unmovable and unresizable.
                resizeButton:SetPoint("BOTTOMRIGHT", castFrame, "BOTTOMRIGHT", -2, 2)
                resizeButton:SetFrameStrata("HIGH")
                if resizeButton.GetRegions then
                    local regions = { resizeButton:GetRegions() }
                    for ri = 1, #regions do
                        local regionFrame = regions[ri]
                        if regionFrame and regionFrame:IsObjectType("Texture") then
                            regionFrame:SetTexture(
                                "Interface\\AddOns\\CludesUI\\media\\icons\\resize_element.png"
                            )
                            regionFrame:SetDesaturated(true)
                            regionFrame:SetVertexColor(1, 1, 1)
                            regionFrame:SetAllPoints()
                        end
                    end
                end
                resizeButton:SetAlpha(0.4)
            end -- not stock
            -- Arms the interaction follower: a resize drag starts and stays on
            -- this button, and the panel must follow it live.
            resizeButton:HookScript("OnEnter", function(self)
                if not stock then self:SetAlpha(0.75) end
                if CHAT.FollowArm then CHAT.FollowArm() end
            end)
            resizeButton:HookScript("OnLeave", function(self)
                if not stock then self:SetAlpha(0.4) end
                if CHAT.FollowRelease then CHAT.FollowRelease() end
            end)
        end)
    end

    -- Main chat: our grip is the sole resize surface (engine-driven sizing;
    -- see BuildMainChatResizeGrip for the hard constraints).
    if castFrame == _G.ChatFrame1 and mod._BuildMainChatResizeGrip then
        mod._BuildMainChatResizeGrip(castFrame)
    end

    -- Same class as the button frame above: FCF_UpdateScrollbarAnchors anchors
    -- Blizzard's own ScrollBar TO this button, and FCF_SetLocked reaches it via
    -- FCF_UpdateResizeButton during the dock. Alpha, NOT SetParent.
    if castFrame.ScrollToBottomButton then
        local scrollBar = castFrame.ScrollToBottomButton
        scrollBar:SetAlpha(0)
        scrollBar:EnableMouse(false)
        -- Blizzard ANIMATES this button's alpha (UIFrameFadeIn to .65 on
        -- activity, SetAlpha(1) while its Flash texture is UIFrameFlashing),
        -- so no alpha assert can ever win. Hidden wins: their fade-in
        -- re-Shows it and this post-hook re-hides it in the same execution,
        -- before anything renders (the Prat button-hide shape).
        if not CFD(scrollBar).hideHooked then
            CFD(scrollBar).hideHooked = true
            scrollBar:HookScript("OnShow", scrollBar.Hide)
        end
        scrollBar:Hide()
    end

    -- Strip ALL Blizzard textures from the chat frame. Texture objects only, and
    -- skips anything we created (marked with _cuiOwned). The stock styles skip
    -- the strip: that art -- the chat background and border Blizzard's own
    -- hover fade animates -- IS their look (a pure skip, no new write). WoW
    -- Forever strips it (its bronze frames are ours).
    local stockArt = mod.ChatStockArt()
    if castFrame.GetRegions and not stockArt then
        local regions = { castFrame:GetRegions() }
        for index = 1, #regions do
            local regionFrame = regions[index]
            if regionFrame and regionFrame:IsObjectType("Texture") and not regionFrame._cuiOwned then
                regionFrame:SetTexture("")
                regionFrame:SetAtlas("")
                regionFrame:SetAlpha(0)
            end
        end
    end
    if castFrame.Background and not stockArt then
        castFrame.Background:SetAlpha(0)
        if castFrame.Background.GetRegions then
            local regions = { castFrame.Background:GetRegions() }
            for index = 1, #regions do
                local regionFrame = regions[index]
                if regionFrame and regionFrame:IsObjectType("Texture") then regionFrame:SetAlpha(0) end
            end
        end
    end

    castFrame:SetHyperlinksEnabled(true)

    -- Combat Log: replace Blizzard's filter tab bar with a dark bar matching
    -- the chat panel's width and style (the stock styles keep Blizzard's bar).
    if name == "ChatFrame2" and not stockArt then
        local quickButtons = _G.CombatLogQuickButtonFrame_Custom
        if quickButtons and not CFD(quickButtons).skinned then
            CFD(quickButtons).skinned = true
            -- WoW Forever: the bar keeps Blizzard's seat, inside the kit's
            -- frame round the combat log (ApplyInputPosition), on its fill.
            local fv = mod.ChatForever()

            if quickButtons.GetRegions then
                local regions = { quickButtons:GetRegions() }
                for index = 1, #regions do
                    local regionFrame = regions[index]
                    if regionFrame and regionFrame:IsObjectType("Texture") then regionFrame:SetAlpha(0) end
                end
            end

            -- Flush: filter bar bottom meets bg top (cf top + 3), width matches
            -- the panel.
            if not fv then
                quickButtons:ClearAllPoints()
                quickButtons:SetPoint("BOTTOMLEFT", castFrame, "TOPLEFT", -10, 3)
                quickButtons:SetPoint("BOTTOMRIGHT", castFrame, "TOPRIGHT", 10, 3)
                quickButtons:SetHeight(24)

                local qbfBg = quickButtons:CreateTexture(nil, "BACKGROUND")
                qbfBg:SetAllPoints()
                qbfBg:SetColorTexture(BG_R, BG_G, BG_B, 1)
            end

            -- Bottom divider separating filter tabs from messages
            local onePx = (Pix and Pix.mult) or 1
            local quickDivider = quickButtons:CreateTexture(nil, "OVERLAY", nil, 7)
            quickDivider._cuiOwned = true
            quickDivider:SetHeight(onePx)
            quickDivider:SetColorTexture(1, 1, 1, 0.06)
            quickDivider:SetPoint("BOTTOMLEFT", quickButtons, "BOTTOMLEFT", 0, 0)
            quickDivider:SetPoint("BOTTOMRIGHT", quickButtons, "BOTTOMRIGHT", 0, 0)
            if Pix and Pix.DisablePixelSnap then Pix.DisablePixelSnap(quickDivider) end

            -- Restyle filter buttons; accent-color the active one.
            local ACC = CUI.CLUDES_GREEN or { r = 0.05, g = 0.82, b = 0.61 }
            local clFilterBtns = {}
            local function UpdateCLFilterColors()
                for _, button in ipairs(clFilterBtns) do
                    local fontStr = button:GetFontString()
                    if not fontStr then return end
                    local isActive = button.GetChecked and button:GetChecked()
                    if fv then
                        -- WoW Forever: the kit's gold and tan.
                        local c = isActive and CHAT.FV.gold or CHAT.FV.tan
                        fontStr:SetTextColor(c[1], c[2], c[3], isActive and 1 or 0.8)
                    elseif isActive then
                        local eg = CUI.CLUDES_GREEN or ACC
                        fontStr:SetTextColor(eg.r, eg.g, eg.b, 1)
                    else
                        fontStr:SetTextColor(1, 1, 1, 0.5)
                    end
                end
            end
            if quickButtons.GetChildren then
                local children = { quickButtons:GetChildren() }
                for index = 1, #children do
                    local button = children[index]
                    if
                        button and button:IsObjectType("CheckButton")
                        or (button and button:IsObjectType("Button"))
                    then
                        clFilterBtns[#clFilterBtns + 1] = button
                        if button.GetRegions then
                            local regions = { button:GetRegions() }
                            for jdx = 1, #regions do
                                local rgn = regions[jdx]
                                if rgn and rgn:IsObjectType("Texture") then rgn:SetAlpha(0) end
                            end
                        end
                        local fontStr = button:GetFontString()
                        if fontStr then fontStr:SetFont(GetFont(), 12, "") end
                        button:HookScript("OnClick", UpdateCLFilterColors)
                    end
                end
            end
            UpdateCLFilterColors()
            CUI.RegAccent({ type = "callback", fn = UpdateCLFilterColors })

            -- One-time alpha set. NEVER hooksecurefunc SetAlpha here -- that
            -- taints execution during whisper/tab processing.
            quickButtons:SetAlpha(1)

            -- The chat bg is NOT extended upward: the filter bar has its own bg,
            -- and keeping both chat frame bgs the same size stops the visual
            -- jump when switching between General and Combat Log tabs.
        end
    end

    -- Blizzard's scrollbar (and its arrows) lives in the engine's hidden
    -- container; our windows carry their own thin scrollbar instead.
end

Inner.SkinChatFrame = SkinChatFrame
Inner.broken = false
