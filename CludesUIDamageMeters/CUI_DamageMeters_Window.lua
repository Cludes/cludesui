if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_DamageMeters_Window.lua
--
--  The context menu and CreateDMWindow, the factory of one meter window.
--  Reads the earlier Damage Meters files through ns and ns._dmInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._dmInternals
-- CludesUIDamageMeters.lua or an earlier CUI_DamageMeters_*.lua file
-- failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local CUI = CludesUI
local Loc = _G.CludesUI.L

local BAR_POOL_SIZE, BAR_TEX, DB = Inner.BAR_POOL_SIZE, Inner.BAR_TEX, Inner.DB
local DM_TYPE_ICONS, DM_TYPE_NAMES, GetHeaderH = Inner.DM_TYPE_ICONS, Inner.DM_TYPE_NAMES, Inner.GetHeaderH
local ICON_ALPHA, ICON_HOVER_ALPHA = Inner.ICON_ALPHA, Inner.ICON_HOVER_ALPHA
local MAX_WINDOWS, MEDIA, MIN_H, MIN_W = Inner.MAX_WINDOWS, Inner.MEDIA, Inner.MIN_H, Inner.MIN_W
local PEAK_BUDGET, RANK_STRINGS, RESIZE_ICON = Inner.PEAK_BUDGET, Inner.RANK_STRINGS, Inner.RESIZE_ICON
local SESSION_TYPE_NAMES, SESSION_TYPES = Inner.SESSION_TYPE_NAMES, Inner.SESSION_TYPES
local _feignDeathGUIDs, _windows = Inner._feignDeathGUIDs, Inner._windows
local ApplyHeaderButtonsHoverVisibility = Inner.ApplyHeaderButtonsHoverVisibility
local CleanupFeignCache, GetBookmarks = Inner.CleanupFeignCache, Inner.GetBookmarks
local GetCurrentViewDuration = Inner.GetCurrentViewDuration
local LayoutHeaderButtons, WinDB, AbbrevNumber = Inner.LayoutHeaderButtons, Inner.WinDB, Inner.AbbrevNumber
local AggregateEnemyPlayers, ApplyBarTexture = Inner.AggregateEnemyPlayers, Inner.ApplyBarTexture
local BuildPlayerTargets, FormatBarValue = Inner.BuildPlayerTargets, Inner.FormatBarValue
local FormatTimer, GetAccentRGB = Inner.FormatTimer, Inner.GetAccentRGB
local GetBarTexturePath, GetBreakdownDuration = Inner.GetBarTexturePath, Inner.GetBreakdownDuration
local PhysicalPixels, ResolveIcon, SetDMFont = Inner.PhysicalPixels, Inner.ResolveIcon, Inner.SetDMFont
local StripRealm, _hoverPollFrame, _ttBars = Inner.StripRealm, Inner._hoverPollFrame, Inner._ttBars
local ApplyInheritedBlizzardBorder = Inner.ApplyInheritedBlizzardBorder
local EnsureTooltipFrame, HideBarTooltip = Inner.EnsureTooltipFrame, Inner.HideBarTooltip
local HideTTTargets, TT_HDR_H, TT_WIDTH = Inner.HideTTTargets, Inner.TT_HDR_H, Inner.TT_WIDTH
local SetActiveRow, SetCombatEndTime = Inner.SetActiveRow, Inner.SetCombatEndTime
local SetCurViewFrozenDur = Inner.SetCurViewFrozenDur

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._dmInternals, which hands the value to every copy.
local _ttFrame
Inner.ttFrameSetters[#Inner.ttFrameSetters + 1] = function(v) _ttFrame = v end

-- The player's GUID: set at login by CUI_DamageMeters_Lifecycle.lua
-- (SetPlayerGUID), read here only.
local _playerGUID
Inner.playerGUIDSetters[#Inner.playerGUIDSetters + 1] = function(v) _playerGUID = v end

-- EDM Context Menu (shared)
local _edmMenu, _edmSub
local CTX_ITEM_H = 22
local CTX_HDR_H = 20
local CTX_SEP_H = 7
local CTX_PAD = 0
local CTX_MIN_W = 100
local CTX_FONT_SZ = 11
local CTX_ARROW_ICON = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-arrow.png"

local function MakeMenuPanel(level)
    local RS = CUI.RESKIN or {}
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(200 + (level or 0) * 10)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    local backdrop = frame:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(RS.BG_R or 0.067, RS.BG_G or 0.067, RS.BG_B or 0.067, RS.CTX_ALPHA or 0.95)
    -- WoW Forever: Forever's dropdown panel in place of the CUI border.
    if not mod.DMFvMenuArt(frame, backdrop) then
        local PP_L = CUI.PP
        if PP_L and PP_L.CreateBorder then PP_L.CreateBorder(frame, 1, 1, 1, RS.BRD_ALPHA or 0.18, 1) end
        ApplyInheritedBlizzardBorder(frame, "popupMenu")
    end
    frame._pool = {}
    frame:Hide()
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:SetScript("OnEvent", function(self) self:Hide() end)
    return frame
end

local function EnsureMenuRow(dropMenu, index)
    local row = dropMenu._pool[index]
    if row then return row end
    local fontFile = (CUI.GetFontPath("damageMeters")) or "Fonts\\FRIZQT__.TTF"
    local outline = (CUI.GetFontOutlineFlag("damageMeters")) or ""
    row = CreateFrame("Button", nil, dropMenu)
    row._hl = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row._hl:SetAllPoints()
    row._lbl = row:CreateFontString(nil, "OVERLAY")
    row._lbl:SetFont(fontFile, CTX_FONT_SZ, outline)
    row._lbl:SetPoint("LEFT", row, "LEFT", 8, 0)
    row._lbl:SetJustifyH("LEFT")
    row._arrow = row:CreateTexture(nil, "ARTWORK")
    row._arrow:SetTexture(CTX_ARROW_ICON)
    row._arrow:SetSize(19, 19)
    row._arrow:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row._arrow:SetRotation(math.pi / 2)
    row._arrow:SetVertexColor(1, 1, 1, 0.75)
    row._arrow:Hide()
    row._timer = row:CreateFontString(nil, "OVERLAY")
    row._timer:SetFont(fontFile, CTX_FONT_SZ, outline)
    row._timer:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row._timer:SetJustifyH("RIGHT")
    row._timer:SetText("")
    row._sep = row:CreateTexture(nil, "ARTWORK")
    row._sep:SetHeight(1)
    row._sep:SetPoint("LEFT", row, "LEFT", 6, 0)
    row._sep:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row._sep:SetColorTexture(1, 1, 1, 0.12)
    row._sep:SetPoint("CENTER")
    row._sep:Hide()
    dropMenu._pool[index] = row
    return row
end

local function LayoutMenu(dropMenu, itemList, onDismiss, isChild)
    if not dropMenu._fvArt then ApplyInheritedBlizzardBorder(dropMenu, "popupMenu") end
    local fontFile = (CUI.GetFontPath("damageMeters")) or "Fonts\\FRIZQT__.TTF"
    local outline = (CUI.GetFontOutlineFlag("damageMeters")) or ""
    -- WoW Forever: gold active and hovered items, tan timers (no accent).
    local fv = mod.DMForever()
    local ACC = fv and mod.DM_FV.gold or CUI.CLUDES_GREEN
    local hlAlpha = CUI.DD_ITEM_HL_A or 0.08
    for _, region in ipairs(dropMenu._pool) do
        region:Hide()
    end
    if not dropMenu._mfs then dropMenu._mfs = dropMenu:CreateFontString(nil, "OVERLAY") end
    dropMenu._mfs:SetFont(fontFile, CTX_FONT_SZ, outline)
    local maxW = 0
    for _, entry in ipairs(itemList) do
        if type(entry) == "table" and entry.text then
            local extra = ""
            if entry.timerText then extra = "  " .. entry.timerText end
            dropMenu._mfs:SetText(entry.text .. extra)
            local wid = dropMenu._mfs:GetStringWidth() or 0
            if wid > maxW then maxW = wid end
        end
    end
    dropMenu._mfs:SetText("")
    dropMenu._mfs:Hide()
    local menuW = math.max(CTX_MIN_W, maxW + 50)
    local posY = -CTX_PAD
    for index, entry in ipairs(itemList) do
        local row = EnsureMenuRow(dropMenu, index)
        row._sep:Hide()
        row._arrow:Hide()
        row._hl:SetColorTexture(1, 1, 1, 0)
        if row._timer then row._timer:SetText("") end
        if entry == "---" then
            row:SetSize(menuW, CTX_SEP_H)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 0, posY)
            row._lbl:SetText("")
            row._sep:Show()
            row:EnableMouse(false)
            row:SetScript("OnEnter", nil)
            row:SetScript("OnLeave", nil)
            row:SetScript("OnClick", nil)
            row:Show()
            posY = posY - CTX_SEP_H
        elseif entry.isHeader then
            row:SetSize(menuW, CTX_HDR_H)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 0, posY)
            row._lbl:SetFont(fontFile, CTX_FONT_SZ, outline)
            row._lbl:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            row._lbl:SetText(entry.text)
            row._lbl:SetTextColor(1, 0.82, 0, 1)
            row:EnableMouse(false)
            row:SetScript("OnEnter", nil)
            row:SetScript("OnLeave", nil)
            row:SetScript("OnClick", nil)
            row:Show()
            posY = posY - CTX_HDR_H
        else
            local rowH = entry.compact and (CTX_ITEM_H - 2) or CTX_ITEM_H
            row:SetSize(menuW, rowH)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 0, posY)
            row._lbl:SetFont(fontFile, CTX_FONT_SZ, outline)
            row._lbl:SetText(entry.text or "")
            row:EnableMouse(true)
            -- Timer text (accent-colored, right-aligned)
            if entry.timerText and row._timer then
                row._timer:SetFont(fontFile, CTX_FONT_SZ, outline)
                local ar, ag, ab
                if fv then
                    local color = mod.DM_FV.tan
                    ar, ag, ab = color.r, color.g, color.b
                else
                    ar, ag, ab = GetAccentRGB()
                end
                row._timer:SetTextColor(ar, ag, ab, 0.9)
                row._timer:SetText(entry.timerText)
                row._lbl:SetPoint("RIGHT", row._timer, "LEFT", -6, 0)
            else
                row._lbl:SetPoint("RIGHT", row, "RIGHT", -18, 0)
            end
            -- Inline input field (e.g. width entry)
            if entry.isInput then
                row._lbl:SetTextColor(1, 1, 1, 1)
                row:EnableMouse(false)
                row:SetScript("OnEnter", nil)
                row:SetScript("OnLeave", nil)
                row:SetScript("OnClick", nil)
                if not row._editBox then
                    local box = CreateFrame("EditBox", nil, row)
                    box:SetSize(50, 18)
                    box:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                    box:SetFrameLevel(row:GetFrameLevel() + 3)
                    box:SetFont(fontFile, 10, outline)
                    box:SetTextColor(1, 1, 1, 0.9)
                    box:SetJustifyH("CENTER")
                    local boxBg = box:CreateTexture(nil, "BACKGROUND")
                    boxBg:SetAllPoints()
                    boxBg:SetColorTexture(0, 0, 0, 0.4)
                    box:SetAutoFocus(false)
                    box:SetNumeric(true)
                    box:SetMaxLetters(5)
                    row._editBox = box
                end
                row._editBox:Show()
                row._editBox:SetNumber(entry.getValue and entry.getValue() or 0)
                row._editBox:SetScript("OnEnterPressed", function(self)
                    local val = math.max(entry.min or 1, math.floor(self:GetNumber() + 0.5))
                    self:SetNumber(val)
                    if entry.setValue then entry.setValue(val) end
                    self:ClearFocus()
                end)
                row._editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
                row:Show()
                posY = posY - rowH
            end
            if entry.isInput then -- skip normal item logic
            else
                local disabled = entry.isDisabled and entry.isDisabled()
                if entry.children then
                    row._arrow:SetVertexColor(1, 1, 1, disabled and 0.2 or 0.75)
                    row._arrow:Show()
                end
                if disabled then
                    row._lbl:SetTextColor(0.4, 0.4, 0.4, 0.5)
                    row:SetScript("OnEnter", function()
                        if not isChild and _edmSub then _edmSub:Hide() end
                    end)
                    row:SetScript("OnLeave", nil)
                    row:SetScript("OnClick", nil)
                else
                    local active = entry.isActive
                    if active and ACC then
                        row._lbl:SetTextColor(ACC.r, ACC.g, ACC.b, 1)
                    else
                        row._lbl:SetTextColor(1, 1, 1, 1)
                    end
                    if active then
                        row._hl:SetColorTexture(1, 1, 1, hlAlpha)
                        row._hl:Show()
                    end
                    local itemRef = entry
                    row:SetScript("OnEnter", function(self)
                        self._hl:SetColorTexture(1, 1, 1, hlAlpha)
                        if ACC then self._lbl:SetTextColor(ACC.r, ACC.g, ACC.b, 1) end
                        if itemRef.tooltip and CUI.ShowWidgetTooltip then
                            CUI.ShowWidgetTooltip(self, itemRef.tooltip)
                        end
                        if itemRef.children then
                            if not _edmSub then _edmSub = MakeMenuPanel(1) end
                            LayoutMenu(_edmSub, itemRef.children, onDismiss, true)
                            _edmSub:ClearAllPoints()
                            local right = self:GetRight()
                            local subW = _edmSub:GetWidth()
                            local screenW = UIParent:GetRight()
                            if right and subW and screenW and (right + subW) > screenW then
                                _edmSub:SetPoint("TOPRIGHT", self, "TOPLEFT", 0, 0)
                            else
                                _edmSub:SetPoint("TOPLEFT", self, "TOPRIGHT", 0, 0)
                            end
                            _edmSub:Show()
                        elseif not isChild and _edmSub then
                            _edmSub:Hide()
                        end
                    end)
                    row:SetScript("OnLeave", function(self)
                        CUI.HideWidgetTooltip()
                        self._hl:SetColorTexture(1, 1, 1, active and hlAlpha or 0)
                        if active and ACC then
                            self._lbl:SetTextColor(ACC.r, ACC.g, ACC.b, 1)
                        else
                            self._lbl:SetTextColor(1, 1, 1, 1)
                        end
                        if isChild then return end
                        if _edmSub and _edmSub:IsShown() and _edmSub:IsMouseOver() then return end
                        if _edmSub and itemRef.children then _edmSub:Hide() end
                    end)
                    row:SetScript("OnClick", function()
                        if itemRef.children then return end
                        if itemRef.onClick then itemRef.onClick() end
                        if onDismiss then onDismiss() end
                    end)
                end
                if row._editBox then row._editBox:Hide() end
                row:Show()
                posY = posY - rowH
            end -- close isInput else
        end
    end
    dropMenu:SetSize(menuW, math.abs(posY) + CTX_PAD)
end

local _edmMenuAnchor = nil -- tracks which button opened the menu (for toggle)

local function ShowEDMMenu(itemList, anchorBtn)
    if not _edmMenu then
        _edmMenu = MakeMenuPanel(0)
        local acc = 0
        _edmMenu:SetScript("OnUpdate", function(self, elapsed)
            acc = acc + elapsed
            if acc < 0.1 then return end
            acc = 0
            local over = self:IsMouseOver()
                or (_edmSub and _edmSub:IsShown() and _edmSub:IsMouseOver())
                or (_edmMenuAnchor and _edmMenuAnchor:IsMouseOver())
            if not over and IsMouseButtonDown("LeftButton") then self:Hide() end
        end)
        _edmMenu:HookScript("OnHide", function()
            if _edmSub then _edmSub:Hide() end
            _edmMenuAnchor = nil
            CUI.HideWidgetTooltip()
        end)
    end

    -- Toggle: if same button clicked again while menu is open, close it
    if anchorBtn and _edmMenu:IsShown() and _edmMenuAnchor == anchorBtn then
        _edmMenu:Hide()
        return
    end

    local function dismiss()
        _edmMenu:Hide()
        if _edmSub then _edmSub:Hide() end
    end
    LayoutMenu(_edmMenu, itemList, dismiss)
    _edmMenu:ClearAllPoints()
    if anchorBtn then
        _edmMenu:SetPoint("BOTTOMRIGHT", anchorBtn, "TOPRIGHT", 0, 0)
    else
        local scale = _edmMenu:GetEffectiveScale()
        local curX, curY = GetCursorPosition()
        _edmMenu:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", curX / scale, curY / scale)
    end
    _edmMenuAnchor = anchorBtn
    _edmMenu:Show()
end

-- Window Factory: creates a fully independent damage meter window with its own frame tree, bar
-- pool, scroll state, source window, home screen, and refresh cycle. Returns a window table W with all state and a Destroy method.
local UpdateSATimerText -- forward declaration (defined in CUI_DamageMeters_Timer.lua)
Inner.updateSATimerTextSetters[#Inner.updateSATimerTextSetters + 1] = function(v) UpdateSATimerText = v end

local function CreateDMWindow(winIdx)
    -- Function-locals, not upvalues: this function sits at Lua 5.1's
    -- 60-upvalue cap (see the notes at ns._AnchorBreakdownFrame and the
    -- syncSegments switch), so the secret helpers come back in through ns.
    local IsSecret, IsOwnRow = mod._IsSecret, mod._IsOwnRow
    local wdb = WinDB(winIdx)
    local Win = {}
    Win.idx = winIdx
    Win.curDMType = wdb.curDMType or Enum.DamageMeterType.DamageDone
    -- A type this client does not offer (WoW Forever's Threat without Forever
    -- Essentials, or in a profile brought elsewhere) reads as Damage Done; the
    -- saved choice stays.
    if not DM_TYPE_NAMES[Win.curDMType] then Win.curDMType = Enum.DamageMeterType.DamageDone end
    Win.curSession = wdb.curSession or Enum.DamageMeterSessionType.Current
    Win.curSessionID = nil
    Win.visibleCount = 0
    Win.isHovered = false
    Win.resizing = false
    Win.windowLocked = wdb.locked or false
    Win.snapDisabled = wdb.snapDisabled or false
    Win.sourceOpen = false
    Win.sourceGUID = nil
    Win.sourceCreatureID = nil
    Win.sourceClass = nil
    Win.cachedSources = nil
    Win.stickyAtTop = false
    Win.stickyGuard = false
    Win.refreshElapsed = 0
    Win.hdrIcons = {}
    local conf = DB()
    local Pix = CUI and CUI.PP

    -- Forward declarations (defined later in this function)
    local RefreshHome
    local RefreshUI
    local homeFrame

    -- Row factory
    local function MakeRow(hostFrame)
        local barFrame = {}
        barFrame.row = CreateFrame("Button", nil, hostFrame)
        barFrame.row:SetHeight(18)
        barFrame.row:EnableMouse(true)
        barFrame.row:RegisterForClicks("AnyUp")
        barFrame.fill = CreateFrame("StatusBar", nil, barFrame.row)
        barFrame.fill:SetMinMaxValues(0, 1)
        barFrame.fill:SetValue(0)
        barFrame.fill:SetStatusBarTexture(BAR_TEX)
        barFrame.classIcon = barFrame.fill:CreateTexture(nil, "OVERLAY")
        barFrame.classIcon:SetSize(18, 18)
        barFrame.classIcon:SetPoint("LEFT", barFrame.row, "LEFT", 0, 0)
        local _cz = DB().classIconZoom or 0.06
        barFrame.classIcon:SetTexCoord(_cz, 1 - _cz, _cz, 1 - _cz)
        barFrame.classIcon:Hide()
        -- Per-bar border (lazy-created, only when borderSize > 0)
        function barFrame.ApplyBorder()
            local cfg = DB()
            local sz = cfg.borderSize or 0
            -- Stock-style rows carry no CUI border: Blizzard Style draws the
            -- stock shadow edge, Classic WoW UI a plain bar.
            if sz <= 0 or mod.DMBlizz() or (cfg.barSeparators and mod.DMUseBarSeparators(cfg)) then
                if barFrame._borderFrame then barFrame._borderFrame:Hide() end
                if barFrame._fillBorder then barFrame._fillBorder:Hide() end
                return
            end
            -- Follow-fill mode: fill extent is SECRET geometry, so nothing may measure it
            -- (Backdrop/NineSlice crash on GetWidth of a frame anchored to it) -- render four
            -- plain color strips via engine anchors instead (left fixed, right rides the fill); always solid regardless of Border Style, styled path stays full-row only.
            if cfg.borderFollowFill then
                if barFrame._borderFrame then barFrame._borderFrame:Hide() end
                local fb = barFrame._fillBorder
                if not fb then
                    fb = CreateFrame("Frame", nil, barFrame.row)
                    fb:SetFrameLevel(barFrame.row:GetFrameLevel() + 3)
                    fb:SetPoint("TOPLEFT", barFrame.row, "TOPLEFT")
                    fb:SetSize(1, 1) -- inert; the strips carry the shape
                    fb.top = fb:CreateTexture(nil, "OVERLAY")
                    fb.bottom = fb:CreateTexture(nil, "OVERLAY")
                    fb.left = fb:CreateTexture(nil, "OVERLAY")
                    fb.right = fb:CreateTexture(nil, "OVERLAY")
                    barFrame._fillBorder = fb
                end
                local ft = barFrame.fill:GetStatusBarTexture()
                local anchorL = cfg.borderFollowFillIcon and barFrame.row or barFrame.fill
                local red, green, blue, a =
                    cfg.borderR or 0, cfg.borderG or 0, cfg.borderB or 0, cfg.borderA or 1
                fb.top:SetColorTexture(red, green, blue, a)
                fb.bottom:SetColorTexture(red, green, blue, a)
                fb.left:SetColorTexture(red, green, blue, a)
                fb.right:SetColorTexture(red, green, blue, a)
                fb.top:ClearAllPoints()
                fb.top:SetPoint("TOPLEFT", anchorL, "TOPLEFT", 0, 0)
                fb.top:SetPoint("TOPRIGHT", ft, "TOPRIGHT", 0, 0)
                fb.top:SetHeight(sz)
                fb.bottom:ClearAllPoints()
                fb.bottom:SetPoint("BOTTOMLEFT", anchorL, "BOTTOMLEFT", 0, 0)
                fb.bottom:SetPoint("BOTTOMRIGHT", ft, "BOTTOMRIGHT", 0, 0)
                fb.bottom:SetHeight(sz)
                fb.left:ClearAllPoints()
                fb.left:SetPoint("TOPLEFT", anchorL, "TOPLEFT", 0, -sz)
                fb.left:SetPoint("BOTTOMLEFT", anchorL, "BOTTOMLEFT", 0, sz)
                fb.left:SetWidth(sz)
                fb.right:ClearAllPoints()
                fb.right:SetPoint("TOPRIGHT", ft, "TOPRIGHT", 0, -sz)
                fb.right:SetPoint("BOTTOMRIGHT", ft, "BOTTOMRIGHT", 0, sz)
                fb.right:SetWidth(sz)
                fb:Show()
                return
            end
            if barFrame._fillBorder then barFrame._fillBorder:Hide() end
            if not barFrame._borderFrame then
                barFrame._borderFrame = CreateFrame("Frame", nil, barFrame.row)
                barFrame._borderFrame:SetAllPoints(barFrame.row)
                barFrame._borderFrame:SetFrameLevel(barFrame.row:GetFrameLevel() + 3)
            end
            barFrame._borderFrame:Show()
            local texture = cfg.borderTexture or "solid"
            -- Exact size (nil = the legacy step path) only while it still pairs with sz + tex.
            local px = CludesUI.BorderPx(cfg.borderSizePx, sz, texture)
            CludesUI.ApplyBorderStyle(
                barFrame._borderFrame,
                sz,
                cfg.borderR or 0,
                cfg.borderG or 0,
                cfg.borderB or 0,
                cfg.borderA or 1,
                texture,
                cfg.borderTextureOffset,
                cfg.borderTextureOffsetY,
                cfg.borderTextureShiftX,
                cfg.borderTextureShiftY,
                "damagemeters",
                sz,
                nil,
                px
            )
        end
        barFrame.ApplyBorder()
        function barFrame.ApplyIconBorder()
            local cfg = DB()
            local sz = cfg.iconBorderSize or 0
            local showIcon = (cfg.iconStyle or "spec") ~= "none"
            if not cfg.customIconBorder or sz <= 0 or not showIcon then
                if barFrame._iconBorderFrame then barFrame._iconBorderFrame:Hide() end
                return
            end
            if not barFrame._iconBorderFrame then
                barFrame._iconBorderFrame = CreateFrame("Frame", nil, barFrame.row)
                barFrame._iconBorderFrame:SetFrameLevel(barFrame.row:GetFrameLevel() + 6)
                barFrame._iconBorderFrame:SetAllPoints(barFrame.classIcon) -- tracks icon size/position
            end
            local texture = cfg.iconBorderTexture or "solid"
            local px = CludesUI.BorderPx(cfg.iconBorderSizePx, sz, texture)
            CludesUI.ApplyBorderStyle(
                barFrame._iconBorderFrame,
                sz,
                cfg.iconBorderR or 0,
                cfg.iconBorderG or 0,
                cfg.iconBorderB or 0,
                cfg.iconBorderA or 1,
                texture,
                cfg.iconBorderTextureOffset,
                cfg.iconBorderTextureOffsetY,
                cfg.iconBorderTextureShiftX,
                cfg.iconBorderTextureShiftY,
                "damagemeters_icon",
                sz,
                nil,
                px
            )
            -- After styling: ApplyBorderStyle shows its target, and a border anchored to a hidden icon still draws.
            barFrame._iconBorderFrame:SetShown(barFrame.classIcon:IsShown())
        end
        barFrame.ApplyIconBorder()
        -- Per-bar track background (behind the fill). Default alpha 0 = invisible.
        barFrame._bg = barFrame.row:CreateTexture(nil, "BACKGROUND", nil, -8)
        barFrame._bg:SetAllPoints(barFrame.row)
        function barFrame.ApplyBg()
            local cfg = DB()
            -- Blizzard Style: the stock track and edge; Classic WoW UI keeps
            -- the plain track below.
            if mod.DMStyle() == "blizzard" then
                mod.DMApplyBlizzBarBg(barFrame)
                return
            end
            local a = cfg.barBgAlpha or 0
            -- Class-colored track when enabled: tint the bg with this bar's class color (x bg
            -- alpha), else the custom bg color. classFile can be secret, so guard before indexing
            -- (RAID_CLASS_COLORS[secret] throws); GetClassColor honors global overrides. Mirrors fill/text class coloring.
            if cfg.barBgUseClassColor then
                local castFrame = barFrame._class
                if
                    castFrame
                    and (not issecretvalue or not issecretvalue(castFrame))
                    and RAID_CLASS_COLORS[castFrame]
                then
                    local cc = CUI.GetClassColor(castFrame)
                    if cc then
                        barFrame._bg:SetColorTexture(cc.r, cc.g, cc.b, a)
                        return
                    end
                end
            end
            barFrame._bg:SetColorTexture(cfg.barBgR or 0, cfg.barBgG or 0, cfg.barBgB or 0, a)
        end
        barFrame.ApplyBg()
        local tf = CreateFrame("Frame", nil, barFrame.fill)
        -- Keep text ABOVE the per-bar border (bar.row +3, lazy-created in ApplyBorder); keyed off
        -- bar.row like the border so the two can't tie and let a later-enabled border cover the text
        tf:SetAllPoints(barFrame.fill)
        tf:SetFrameLevel(barFrame.row:GetFrameLevel() + 4)
        barFrame.pos = tf:CreateFontString(nil, "OVERLAY")
        barFrame.pos:SetPoint("LEFT", tf, "LEFT", 3, 0)
        SetDMFont(barFrame.pos, 11)
        barFrame.label = tf:CreateFontString(nil, "OVERLAY")
        barFrame.label:SetPoint("LEFT", barFrame.pos, "RIGHT", 2, 0)
        barFrame.label:SetPoint("RIGHT", tf, "RIGHT", -70, 0)
        barFrame.label:SetJustifyH("LEFT")
        SetDMFont(barFrame.label, 11)
        barFrame.label:SetWordWrap(false)
        barFrame.amount = tf:CreateFontString(nil, "OVERLAY")
        barFrame.amount:SetPoint("RIGHT", tf, "RIGHT", -3, 0)
        barFrame.amount:SetJustifyH("RIGHT")
        SetDMFont(barFrame.amount, 11)
        -- Bar Text X/Y offsets (Bar Text size cogs): re-applies the creation anchors above with
        -- profile offsets added. The label's Y rides its RIGHT point; LEFT already follows bar.pos on both axes.
        barFrame.ApplyTextOffsets = function()
            local c2 = DB()
            local lx, ly = c2.leftTextOffsetX or 0, c2.leftTextOffsetY or 0
            local rx, ry = c2.rightTextOffsetX or 0, c2.rightTextOffsetY or 0
            barFrame.pos:SetPoint("LEFT", tf, "LEFT", 3 + lx, ly)
            barFrame.label:SetPoint("RIGHT", tf, "RIGHT", -70, ly)
            barFrame.amount:SetPoint("RIGHT", tf, "RIGHT", -3 + rx, ry)
        end
        barFrame.ApplyTextOffsets()
        barFrame.row:SetScript("OnClick", function(_, btnFrame)
            if btnFrame == "LeftButton" then
                -- In combat, rows open when a PLAIN guid exists for them:
                -- death recaps (NeverSecret plain ID), the local player's
                -- own breakdown (own GUID plain), and group members via the
                -- identity-exempt token channel (ns._ResolveGroupGUID).
                -- Everything else keeps the block until combat ends.
                if
                    InCombatLockdown()
                    and not IsOwnRow(barFrame._src)
                    and Win.curDMType ~= Enum.DamageMeterType.Deaths
                    and not mod._ResolveGroupGUID(barFrame._src)
                then
                    return
                end
                if barFrame._src and (barFrame._srcGUID or barFrame._src.sourceCreatureID) then
                    -- Deaths without recap data: block click
                    if Win.curDMType == Enum.DamageMeterType.Deaths then
                        local rid = barFrame._src.deathRecapID
                        if not rid or (issecretvalue and issecretvalue(rid)) or rid <= 0 then return end
                        if C_DeathRecap and C_DeathRecap.GetRecapEvents then
                            local success, raw = pcall(C_DeathRecap.GetRecapEvents, rid)
                            if not success or not raw or #raw == 0 then return end
                        end
                    end
                    -- Rows mid-combat carry SECRET GUIDs the getters would
                    -- refuse as arguments; store a plain one instead so the
                    -- panel's per-tick refresh stays legal: own GUID for the
                    -- own row, the identity-exempt token guid for group rows.
                    -- Deaths rows keep their guid untouched (recap path).
                    local unitGuid, cid = barFrame._srcGUID, barFrame._src.sourceCreatureID
                    if IsSecret(unitGuid) or IsSecret(cid) then
                        if IsOwnRow(barFrame._src) then
                            unitGuid, cid = UnitGUID("player"), nil
                        elseif Win.curDMType ~= Enum.DamageMeterType.Deaths then
                            local rg = mod._ResolveGroupGUID(barFrame._src)
                            if rg then
                                unitGuid, cid = rg, nil
                            end
                        end
                    end
                    Win.OpenSource(
                        unitGuid,
                        cid,
                        StripRealm(barFrame._src.name),
                        barFrame._class,
                        barFrame._src.deathRecapID,
                        barFrame._src.name
                    )
                end
            elseif btnFrame == "RightButton" then
                Win.ShowHome()
            end
        end)
        barFrame._hl = tf:CreateTexture(nil, "BACKGROUND")
        barFrame._hl:SetAllPoints(barFrame.row)
        barFrame._hl:SetColorTexture(1, 1, 1, 0.08)
        barFrame._hl:Hide()
        barFrame.row:SetScript("OnEnter", function()
            barFrame._hl:Show()
            -- Threat rows (WoW Forever) have no breakdown to show.
            if Win.curDMType == "threat" then return end
            -- Deaths without recap: show "no recap available" tooltip
            if Win.curDMType == Enum.DamageMeterType.Deaths and barFrame._src then
                local rid = barFrame._src.deathRecapID
                local hasRecap = rid and not (issecretvalue and issecretvalue(rid)) and rid > 0
                if hasRecap and C_DeathRecap and C_DeathRecap.GetRecapEvents then
                    local success, raw = pcall(C_DeathRecap.GetRecapEvents, rid)
                    if not success or not raw or #raw == 0 then hasRecap = false end
                end
                if not hasRecap then
                    EnsureTooltipFrame()
                    local playerName = StripRealm(barFrame._src.name, barFrame._src)
                    _ttFrame._hdrText:SetText(CludesUI.Lf("%1$s's Death Recap", playerName))
                    local cfg2 = DB()
                    local hc = cfg2.hdrBgColor
                    local hR = hc and hc.r or 0x1B / 255
                    local hG = hc and hc.g or 0x1B / 255
                    local hB = hc and hc.b or 0x1B / 255
                    mod.DMPaintHeaderBg(_ttFrame._hdrBg, hR, hG, hB, cfg2.hdrBgAlpha or 1)
                    local tR, tG, tB
                    if cfg2.hdrTextUseAccent ~= false then
                        tR, tG, tB = mod.DMTitleRGB()
                    else
                        local tc = cfg2.hdrTextColor
                        tR = tc and tc.r or 1
                        tG = tc and tc.g or 1
                        tB = tc and tc.b or 1
                    end
                    _ttFrame._hdrText:SetTextColor(tR, tG, tB, 1)
                    for bi = 1, #_ttBars do
                        if _ttBars[bi] then _ttBars[bi].row:Hide() end
                    end
                    HideTTTargets()
                    _ttFrame._combatMsg:SetText(CludesUI.L("No death recap available"))
                    _ttFrame._combatMsg:Show()
                    _ttFrame:SetSize(TT_WIDTH, TT_HDR_H + 40)
                    mod._AnchorBreakdownFrame(barFrame.row, Win.frame)
                    _ttFrame:Show()
                    return
                end
            end
            -- The combat message only for rows the API keeps unreadable:
            -- own breakdown, death recaps, enemies inside this season's
            -- dungeons (matched against their listed NPC IDs), and group rows
            -- resolvable through the identity-exempt token channel all fall
            -- through to the normal hover path, whose builders are secret-safe.
            -- Gated on Show Breakdown on Hover like ShowBarTooltip: with the option off
            -- this branch still showed the disclaimer for ally rows.
            if
                InCombatLockdown()
                and DB().showHoverTooltip ~= false
                and not IsOwnRow(barFrame._src)
                and Win.curDMType ~= Enum.DamageMeterType.Deaths
                and not (Win.curDMType == Enum.DamageMeterType.EnemyDamageTaken and mod.DMSeasonMobsHere())
                and not mod._ResolveGroupGUID(barFrame._src)
            then
                EnsureTooltipFrame()
                -- Show header with player name + type
                local playerName = StripRealm(barFrame._src and barFrame._src.name, barFrame._src)
                local typeName = Loc(DM_TYPE_NAMES[Win.curDMType] or "Damage Done")
                _ttFrame._hdrText:SetText(CludesUI.Lf("%1$s's %2$s Breakdown", playerName, typeName))
                local cfg2 = DB()
                local hc = cfg2.hdrBgColor
                local hR = hc and hc.r or 0x1B / 255
                local hG = hc and hc.g or 0x1B / 255
                local hB = hc and hc.b or 0x1B / 255
                mod.DMPaintHeaderBg(_ttFrame._hdrBg, hR, hG, hB, cfg2.hdrBgAlpha or 1)
                local tR, tG, tB
                if cfg2.hdrTextUseAccent ~= false then
                    tR, tG, tB = mod.DMTitleRGB()
                else
                    local tc = cfg2.hdrTextColor
                    tR = tc and tc.r or 1
                    tG = tc and tc.g or 1
                    tB = tc and tc.b or 1
                end
                _ttFrame._hdrText:SetTextColor(tR, tG, tB, 1)
                -- Hide bars, show combat message
                for bi = 1, #_ttBars do
                    if _ttBars[bi] then _ttBars[bi].row:Hide() end
                end
                HideTTTargets()
                _ttFrame._combatMsg:SetText(CludesUI.L("Detailed information is\nsecret while in combat"))
                _ttFrame._combatMsg:Show()
                _ttFrame:SetSize(TT_WIDTH, TT_HDR_H + 40)
                mod._AnchorBreakdownFrame(barFrame.row, Win.frame)
                _ttFrame:Show()
                return
            end
            SetActiveRow(barFrame)
            barFrame._win = Win
            _hoverPollFrame:Show()
        end)
        barFrame.row:SetScript("OnLeave", function()
            barFrame._hl:Hide()
            SetActiveRow(nil)
            _hoverPollFrame:Hide()
            HideBarTooltip()
        end)
        barFrame._src = nil
        barFrame._srcGUID = nil
        barFrame._class = nil
        barFrame._win = Win
        barFrame.row:Hide()
        return barFrame
    end

    -- Spell tooltip on breakdown-row hover: uses the real GameTooltip for full native info
    -- (cooldown/range/cast time/description) -- deliberate exception to the no-GameTooltip rule,
    -- which exists to avoid taint in secure/chat-frame contexts; these rows are our own non-secure
    -- frames so SetOwner+SetSpellByID+Show is safe. Anchored LEFT via ANCHOR_NONE + manual SetPoint; bar._spellID is nil on non-spell rows, and secret-value + valid-spell checks guard the rest -- ShowWidgetTooltip's combat suppression does not apply here, so these guards are the only protection.
    local function ShowSpellRowTooltip(anchor, spellID)
        if not spellID or type(spellID) ~= "number" then return end
        local conf = DB()
        if conf and conf.showSpellTooltips == false then return end
        if issecretvalue and issecretvalue(spellID) then return end
        -- Only show for a real, resolvable spell.
        local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
        if not name or (issecretvalue and issecretvalue(name)) then return end
        GameTooltip:SetOwner(anchor, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -6, 0)
        GameTooltip:SetSpellByID(spellID)
        GameTooltip:Show()
    end

    local function MakeSpellRow(hostFrame)
        local barFrame = {}
        barFrame.row = CreateFrame("Button", nil, hostFrame)
        barFrame.row:SetHeight(18)
        barFrame.row:EnableMouse(true)
        barFrame.row:RegisterForClicks("AnyUp")
        barFrame.fill = CreateFrame("StatusBar", nil, barFrame.row)
        barFrame.fill:SetMinMaxValues(0, 1)
        barFrame.fill:SetValue(0)
        barFrame.fill:SetStatusBarTexture(BAR_TEX)
        -- Blizzard Style: the same track and edge as the main rows (Classic
        -- WoW UI rows stay plain).
        if mod.DMStyle() == "blizzard" then
            barFrame._bg = barFrame.row:CreateTexture(nil, "BACKGROUND")
            mod.DMApplyBlizzBarBg(barFrame)
        end
        barFrame.classIcon = barFrame.fill:CreateTexture(nil, "OVERLAY")
        barFrame.classIcon:SetSize(18, 18)
        barFrame.classIcon:SetPoint("LEFT", barFrame.row, "LEFT", 0, 0)
        barFrame.classIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        barFrame.classIcon:Hide()
        local tf = CreateFrame("Frame", nil, barFrame.fill)
        tf:SetAllPoints(barFrame.fill)
        tf:SetFrameLevel(barFrame.fill:GetFrameLevel() + 2)
        barFrame.label = tf:CreateFontString(nil, "OVERLAY")
        barFrame.label:SetPoint("LEFT", tf, "LEFT", 3, 0)
        barFrame.label:SetPoint("RIGHT", tf, "RIGHT", -70, 0)
        barFrame.label:SetJustifyH("LEFT")
        SetDMFont(barFrame.label, 11)
        barFrame.label:SetWordWrap(false)
        barFrame.amount = tf:CreateFontString(nil, "OVERLAY")
        barFrame.amount:SetPoint("RIGHT", tf, "RIGHT", -3, 0)
        barFrame.amount:SetJustifyH("RIGHT")
        SetDMFont(barFrame.amount, 11)
        barFrame.row:SetScript("OnClick", function() Win.CloseSource() end)
        barFrame.row:SetScript("OnEnter", function(self) ShowSpellRowTooltip(self, barFrame._spellID) end)
        barFrame.row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        barFrame._spellID = nil
        barFrame.row:Hide()
        return barFrame
    end

    -- Main container
    local widget = CreateFrame("Frame", "CludesUIDMFrame" .. winIdx, UIParent)
    widget:SetSize(wdb.width or 300, wdb.height or 200)
    widget:SetClampedToScreen(true)
    widget:SetMovable(true)
    Win.frame = widget

    mod.ApplyWinPosition(widget, wdb, winIdx)
    -- Used by unlock mode's applyPosition callback; W.idx (not winIdx) so it survives re-indexing
    Win.ApplyPosition = function() mod.ApplyWinPosition(widget, wdb, Win.idx) end

    widget._bg = widget:CreateTexture(nil, "BACKGROUND")
    widget._bg:SetPoint("TOPLEFT", widget, "TOPLEFT", 0, -GetHeaderH())
    widget._bg:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", 0, 0)
    mod.DMPaintWindowBg(
        widget._bg,
        conf.bgR or 0,
        conf.bgG or 0,
        conf.bgB or 0,
        conf.bgAlpha or 0.75,
        true,
        conf.bgTexture
    )

    -- Header (inside the classic box's line; flush on every other look)
    local ci = mod.DMClassicInset()
    local header = CreateFrame("Frame", nil, widget)
    header:SetHeight(GetHeaderH())
    header:SetPoint("TOPLEFT", widget, "TOPLEFT", ci, -ci)
    header:SetPoint("TOPRIGHT", widget, "TOPRIGHT", -ci, -ci)
    header:SetFrameLevel(widget:GetFrameLevel() + 5)
    Win.header = header

    -- Independent overlay target so the frame border can start at the window top or below the header without affecting window layout
    local windowBorderTarget = CreateFrame("Frame", nil, widget)
    windowBorderTarget:EnableMouse(false)
    Win.windowBorderTarget = windowBorderTarget
    mod.DMSetWindowBorderLayer(Win, conf)

    do
        local hc = conf.hdrBgColor
        local hR = hc and hc.r or 0x1B / 255
        local hG = hc and hc.g or 0x1B / 255
        local hB = hc and hc.b or 0x1B / 255
        header._hdrBg = header:CreateTexture(nil, "BACKGROUND")
        header._hdrBg:SetAllPoints()
        mod.DMPaintHeaderBg(header._hdrBg, hR, hG, hB, conf.hdrBgAlpha or 1)
    end
    header._bottomBorder = header:CreateTexture(nil, "OVERLAY", nil, 7)
    header._bottomBorder:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    header._bottomBorder:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    if not mod.DMClassicSeparator(header._bottomBorder, PhysicalPixels(1)) then
        local size = conf.hdrBottomBorderSize or 0
        local color = conf.hdrBottomBorderColor or {}
        header._bottomBorder:SetHeight(PhysicalPixels(size))
        header._bottomBorder:SetColorTexture(color.r or 0, color.g or 0, color.b or 0, color.a or 1)
        header._bottomBorder:SetShown(size > 0 and not mod.DMBlizz())
    end

    local hdrFS = conf.hdrFontSize or 11
    local txOX, txOY = conf.hdrTextOffX or 0, conf.hdrTextOffY or 0
    Win.titleText = header:CreateFontString(nil, "OVERLAY")
    SetDMFont(Win.titleText, hdrFS)
    Win.titleText:SetPoint("LEFT", header, "LEFT", 6 + txOX, txOY + mod.DMHdrLift(conf.hdrHeight))
    do
        local tR, tG, tB
        if conf.hdrTextUseAccent ~= false then
            tR, tG, tB = mod.DMTitleRGB()
        else
            local tc = conf.hdrTextColor
            tR = tc and tc.r or 1
            tG = tc and tc.g or 1
            tB = tc and tc.b or 1
        end
        Win.titleText:SetTextColor(tR, tG, tB, 1)
    end
    Win._fullTitle = Loc("Damage Done")
    Win.titleText:SetText(Loc("Damage Done"))

    Win.timerText = header:CreateFontString(nil, "OVERLAY")
    SetDMFont(Win.timerText, hdrFS)
    Win.timerText:SetTextColor(1, 1, 1, 0.7)
    Win.timerText:SetPoint("LEFT", Win.titleText, "RIGHT", 4, 0)
    Win.timerText:SetText("(0:00)")
    if wdb.hideTimer then Win.timerText:Hide() end

    if CUI.RegAccent then
        -- Propagates a live accent color change to header text, header icons, bars (via
        -- Refresh), and home screen cards (via RefreshHome), each gated on its own accent-use toggle
        CUI.RegAccent({
            type = "callback",
            fn = function(red, green, blue)
                -- A parked window re-reads the accent when it is brought back (W.Reapply).
                if Win._parked then return end
                local cfg = DB()
                -- (WoW Forever's title keeps its gold.)
                if cfg.hdrTextUseAccent ~= false and not mod.DMForever() then
                    Win.titleText:SetTextColor(red, green, blue, 1)
                end
                if cfg.iconColorUseAccent then
                    for _, ic in ipairs(Win.hdrIcons) do
                        if not ic._hdrArt then ic:SetVertexColor(red, green, blue, ICON_ALPHA) end
                    end
                end
                Win.Refresh()
                if homeFrame and homeFrame:IsShown() then RefreshHome() end
            end,
        })
    end

    -- Header buttons (size and gap follow the style: ns.DMHdrIconSize)
    local btnSize = mod.DMHdrIconSize(conf)
    local btnPad = mod.DMHdrIconPad()

    Win.hdrIcons = {}
    local function IconColor()
        local cfg = DB()
        if cfg.iconColorUseAccent then return GetAccentRGB() end
        local ic = cfg.iconColor
        return ic and ic.r or 1, ic and ic.g or 1, ic and ic.b or 1
    end

    -- artKey: the header key whose stock-style art replaces the CUI glyph
    -- under a stock style (ns.DM_HDR_ART); the glyph stays where none exists.
    local function NewHeaderBtn(texFile, xOff, tooltip, onClick, artKey)
        local button = CreateFrame("Button", nil, header)
        button:SetSize(btnSize, btnSize)
        button:SetPoint("RIGHT", header, "RIGHT", xOff, mod.DMHdrLift())
        button:SetFrameLevel(header:GetFrameLevel() + 2)
        local ir, ig, ib = IconColor()
        local iconTex = button:CreateTexture(nil, "ARTWORK")
        iconTex:SetAllPoints()
        button._hdrIcon = iconTex
        if not mod.DMPaintHdrArt(iconTex, artKey) then
            iconTex:SetTexture(MEDIA .. texFile)
            iconTex:SetDesaturated(true)
            iconTex:SetVertexColor(ir, ig, ib, ICON_ALPHA)
        end
        Win.hdrIcons[#Win.hdrIcons + 1] = iconTex
        button:SetScript("OnEnter", function(self)
            if not mod.DMHdrHover(iconTex, true) then
                local red, green, blue = IconColor()
                iconTex:SetVertexColor(red, green, blue, ICON_HOVER_ALPHA)
            end
            -- Suppress tooltip while this button's menu is open
            if _edmMenu and _edmMenu:IsShown() and _edmMenuAnchor == self then return end
            CUI.ShowWidgetTooltip(self, tooltip)
        end)
        button:SetScript("OnLeave", function()
            if not mod.DMHdrHover(iconTex, false) then
                local red, green, blue = IconColor()
                iconTex:SetVertexColor(red, green, blue, ICON_ALPHA)
            end
            CUI.HideWidgetTooltip()
        end)
        button:SetScript("OnClick", function(self)
            CUI.HideWidgetTooltip()
            onClick(self)
        end)
        return button
    end

    Win.settingsBtn = NewHeaderBtn("dm_settings.png", -(btnPad + 2), "Settings", function()
        -- "Default on M+ Start" submenu: meter type this window switches to when a key starts; "Off" (default) leaves it alone
        local function mythicStartEntry(labelText, dmType)
            return {
                text = labelText,
                isActive = (wdb.mythicStartDMType == dmType),
                onClick = function() wdb.mythicStartDMType = dmType end,
            }
        end
        local mStartChildren = {
            {
                text = Loc("Off"),
                isActive = not wdb.mythicStartDMType,
                onClick = function() wdb.mythicStartDMType = false end,
            },
            "---",
            mythicStartEntry(Loc("Damage Done"), Enum.DamageMeterType.DamageDone),
            mythicStartEntry(Loc("Healing"), Enum.DamageMeterType.HealingDone),
            mythicStartEntry(Loc("Damage Taken"), Enum.DamageMeterType.DamageTaken),
            mythicStartEntry(Loc("Avoidable Damage Taken"), Enum.DamageMeterType.AvoidableDamageTaken),
            mythicStartEntry(Loc("Enemy Damage Taken"), Enum.DamageMeterType.EnemyDamageTaken),
            mythicStartEntry(Loc("Interrupts"), Enum.DamageMeterType.Interrupts),
            mythicStartEntry(Loc("Dispels"), Enum.DamageMeterType.Dispels),
            mythicStartEntry(Loc("Deaths"), Enum.DamageMeterType.Deaths),
        }
        -- An instance rule changed: re-apply every window now, and move the mouseover
        -- scan's cached predicate on next frame (deferred like the hotkey toggle), so a
        -- hover cannot reveal a window the new rule hides.
        local function onRulesChanged()
            for _, wid in ipairs(_windows) do
                wid.UpdateVisibility()
            end
            C_Timer.After(0, CUI.RequestVisibilityUpdate)
        end
        local itemList = {
            {
                text = Loc("Hide in Dungeons"),
                isActive = wdb.hideInDungeon,
                onClick = function()
                    wdb.hideInDungeon = not wdb.hideInDungeon
                    onRulesChanged()
                end,
            },
            {
                text = Loc("Hide in Raids"),
                isActive = wdb.hideInRaid,
                onClick = function()
                    wdb.hideInRaid = not wdb.hideInRaid
                    onRulesChanged()
                end,
            },
            {
                text = Loc("Hide in Delves"),
                noForever = true,
                isActive = wdb.hideInDelve,
                onClick = function()
                    wdb.hideInDelve = not wdb.hideInDelve
                    onRulesChanged()
                end,
            },
            {
                text = Loc("Hide in PvP"),
                isActive = wdb.hideInPvP,
                onClick = function()
                    wdb.hideInPvP = not wdb.hideInPvP
                    onRulesChanged()
                end,
            },
            {
                text = Loc("Hide out of Instances"),
                isActive = wdb.hideOutOfInstance,
                onClick = function()
                    wdb.hideOutOfInstance = not wdb.hideOutOfInstance
                    onRulesChanged()
                end,
            },
            "---",
            {
                text = Loc("Width"),
                isInput = true,
                getValue = function() return math.floor(widget:GetWidth() + 0.5) end,
                setValue = function(v)
                    local leftX, topY = widget:GetLeft(), widget:GetTop()
                    widget:SetSize(math.max(MIN_W, v), widget:GetHeight())
                    if leftX and topY then
                        widget:ClearAllPoints()
                        widget:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", leftX, topY)
                    end
                    wdb.width = math.floor(widget:GetWidth() + 0.5)
                end,
                min = MIN_W,
            },
            {
                text = Loc("Height"),
                isInput = true,
                getValue = function() return math.floor(widget:GetHeight() + 0.5) end,
                setValue = function(v)
                    local leftX, topY = widget:GetLeft(), widget:GetTop()
                    widget:SetSize(widget:GetWidth(), math.max(MIN_H, v))
                    if leftX and topY then
                        widget:ClearAllPoints()
                        widget:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", leftX, topY)
                    end
                    wdb.height = math.floor(widget:GetHeight() + 0.5)
                end,
                min = MIN_H,
            },
            {
                text = Win.snapDisabled and Loc("Enable Snapping") or Loc("Disable Snapping"),
                onClick = function()
                    Win.snapDisabled = not Win.snapDisabled
                    wdb.snapDisabled = Win.snapDisabled
                end,
            },
            {
                text = Loc("Hide Timer"),
                noThreat = true,
                isActive = wdb.hideTimer,
                onClick = function()
                    wdb.hideTimer = not wdb.hideTimer
                    Win.timerText:SetShown(not wdb.hideTimer)
                end,
            },
            {
                text = Loc("Auto Swap Current/Overall"),
                noForever = true,
                tooltip = Loc(
                    "Auto switch your window to overall at the end of an M+ run, and current at the start"
                ),
                isActive = wdb.autoSwapMythic,
                onClick = function() wdb.autoSwapMythic = not wdb.autoSwapMythic end,
            },
            {
                text = Loc("Auto Current on Combat"),
                noThreat = true,
                tooltip = Loc("Entering combat switches this window back to Current if viewing a past segment"),
                isActive = wdb.autoCurrentOnCombat,
                onClick = function() wdb.autoCurrentOnCombat = not wdb.autoCurrentOnCombat end,
            },
            {
                text = Loc("Sync Segment Selection"),
                noThreat = true,
                tooltip = Loc("Selecting a segment switches all synced windows to it"),
                isActive = wdb.syncSegments,
                onClick = function() wdb.syncSegments = not wdb.syncSegments end,
            },
            {
                text = Loc("Default on M+ Start"),
                noForever = true,
                tooltip = Loc("Set your window to this Meter Type on dungeon start"),
                children = mStartChildren,
            },
            {
                text = Loc("Settings"),
                onClick = function() CUI:ShowModule("CludesUIDamageMeters") end,
            },
        }
        -- WoW Forever has no delves and no keystones: the entries only those drive are
        -- left out of the menu there (their saved values stay, and stay inert).
        if CUI.IS_FOREVER then
            for i = #itemList, 1, -1 do
                local e = itemList[i]
                if type(e) == "table" and e.noForever then table.remove(itemList, i) end
            end
        end
        -- A Threat window's list settings head the menu (WoW Forever).
        if Win.curDMType == "threat" and mod.DMThreatMenu then mod.DMThreatMenu(itemList) end
        ShowEDMMenu(itemList, Win.settingsBtn)
    end, "settings")

    Win.segmentBtn = NewHeaderBtn("dm_sheet.png", -(btnSize + btnPad * 2 + 2), Loc("Select Segment"), function()
        -- A Threat list (WoW Forever) has no segments.
        if Win.curDMType == "threat" then return end
        local itemList = {}
        -- Segments first (top of upward menu)
        if C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions then
            local sessions = C_DamageMeter.GetAvailableCombatSessions()
            if sessions and #sessions > 0 then
                local startIdx = math.max(1, #sessions - 19)
                for i = startIdx, #sessions do
                    local cfg = sessions[i]
                    local segName = cfg.name
                    if not segName or (issecretvalue and issecretvalue(segName)) or segName == "" then
                        segName = "Combat"
                    end
                    local segTime = FormatTimer(cfg.durationSeconds or 0)
                    itemList[#itemList + 1] = {
                        text = segName,
                        timerText = segTime,
                        compact = true,
                        isActive = (Win.curSessionID == cfg.sessionID),
                        onClick = function() mod.ApplySegmentSelection(Win, nil, cfg.sessionID) end,
                    }
                end
            end
        end
        -- Divider + Current/Overall at bottom
        itemList[#itemList + 1] = "---"
        for _, sType in ipairs(SESSION_TYPES) do
            itemList[#itemList + 1] = {
                text = Loc(SESSION_TYPE_NAMES[sType] or "Unknown"),
                isActive = (not Win.curSessionID and sType == Win.curSession),
                onClick = function() mod.ApplySegmentSelection(Win, sType, nil) end,
            }
        end
        ShowEDMMenu(itemList, Win.segmentBtn)
    end, "segment")

    -- Switch this window to a meter type (data + icon + refresh). Shared by the
    -- mode button and the "Default on M+ Start" key-start hook so both stay in sync.
    function Win.SetDMType(dmType)
        Win.curDMType = dmType
        wdb.curDMType = dmType
        if Win.CloseSource then Win.CloseSource() end
        -- A full row pass: a Threat list's ranks skip its pull line, so a row that
        -- keeps its slot across the switch would keep that rank.
        Win._barCacheKey = nil
        Win.Refresh()
        if Win._modeIcon then mod.DMSetTypeIcon(Win._modeIcon, dmType) end
        -- Leaving Threat may leave its list with no window (WoW Forever)
        if mod.DMThreatSync then mod.DMThreatSync() end
    end

    Win.modeBtn = NewHeaderBtn(
        "dm_arrow.png",
        -(btnSize * 2 + btnPad * 3 + 2),
        "Switch Meter Type",
        function()
            local function sel(dmType)
                return function() Win.SetDMType(dmType) end
            end
            local function record(labelText, dmType)
                return { text = labelText, onClick = sel(dmType), isActive = (dmType == Win.curDMType) }
            end
            local current = Win.curDMType
            local dmActive = (
                current == Enum.DamageMeterType.DamageDone
                or current == Enum.DamageMeterType.DamageTaken
                or current == Enum.DamageMeterType.AvoidableDamageTaken
                or current == Enum.DamageMeterType.EnemyDamageTaken
            )
            local actActive = (
                current == Enum.DamageMeterType.Interrupts
                or current == Enum.DamageMeterType.Dispels
                or current == Enum.DamageMeterType.Deaths
            )
            local itemList = {
                {
                    text = Loc("Damage"),
                    isActive = dmActive,
                    children = {
                        record(Loc("Damage Done"), Enum.DamageMeterType.DamageDone),
                        record(Loc("Damage Taken"), Enum.DamageMeterType.DamageTaken),
                        record(Loc("Avoidable Damage Taken"), Enum.DamageMeterType.AvoidableDamageTaken),
                        record(Loc("Enemy Damage Taken"), Enum.DamageMeterType.EnemyDamageTaken),
                    },
                },
                record(Loc("Healing"), Enum.DamageMeterType.HealingDone),
                {
                    text = Loc("Actions"),
                    isActive = actActive,
                    children = {
                        record(Loc("Interrupts"), Enum.DamageMeterType.Interrupts),
                        record(Loc("Dispels"), Enum.DamageMeterType.Dispels),
                        record(Loc("Deaths"), Enum.DamageMeterType.Deaths),
                    },
                },
            }
            -- WoW Forever with Forever Essentials: its threat list
            if DM_TYPE_NAMES.threat then itemList[#itemList + 1] = record(Loc("Threat"), "threat") end
            ShowEDMMenu(itemList, Win.modeBtn)
        end
    )
    -- Set mode icon to current DM type icon
    Win._modeIcon = Win.hdrIcons[#Win.hdrIcons]
    mod.DMSetTypeIcon(Win._modeIcon, Win.curDMType)

    -- + (new window) or x (close window) button, left of mode icon
    local winActionIcon = (winIdx == 1) and (MEDIA .. "dm_open.png") or (MEDIA .. "dm_close.png")
    local winActionTip = (winIdx == 1) and Loc("New Window") or Loc("Close Window")
    local winActionKey = (winIdx == 1) and "open" or "close"
    Win.winActionBtn = NewHeaderBtn(
        "dm_settings.png",
        -(btnSize * 4 + btnPad * 5 + 2),
        winActionTip,
        function()
            if winIdx ~= 1 and Win.windowLocked then return end
            if winIdx == 1 then
                if #_windows >= MAX_WINDOWS then return end
                local newIdx2 = #_windows + 1
                local srcW2 = widget:GetWidth()
                local srcH2 = widget:GetHeight()
                local srcLeft2 = widget:GetLeft()
                local GAP = 10

                -- Find the highest top and lowest bottom among all existing windows
                local highestTop = widget:GetTop() or 0
                local lowestBot = widget:GetBottom() or 0
                for _, wid in ipairs(_windows) do
                    if wid.frame then
                        local t = wid.frame:GetTop()
                        local b = wid.frame:GetBottom()
                        if t and t > highestTop then highestTop = t end
                        if b and b < lowestBot then lowestBot = b end
                    end
                end

                -- Try above first (new bottom = highest top + gap); if that clears the screen top, place below the lowest window instead
                local screenTop2 = UIParent:GetTop() or 0
                local newTop2 = highestTop + srcH2 + GAP
                if newTop2 > screenTop2 then newTop2 = lowestBot - GAP end

                local nwdb = WinDB(newIdx2)
                nwdb.width = math.floor(srcW2 + 0.5)
                nwdb.height = math.floor(srcH2 + 0.5)
                nwdb.position = { x = srcLeft2, y = newTop2 }
                -- A closed window comes back before a new one is built
                local nw = mod.DMAcquireWindow(newIdx2)
                _windows[newIdx2] = nw
                if mod.ApplyWindowBorder then mod.ApplyWindowBorder() end
                -- Persist count
                local cfg = DB()
                cfg.windowCount = newIdx2
                mod.RegisterDMUnlock()
                nw.ShowHome()
            else
                Win.Destroy()
            end
        end,
        winActionKey
    )
    -- Override icon texture (the stock art, when any, was painted by key);
    -- close icon 2px larger for visibility
    do
        local iconTex = Win.hdrIcons[#Win.hdrIcons]
        if not iconTex._hdrArt then iconTex:SetTexture(winActionIcon) end
        if winIdx ~= 1 then Win._closeIconTex = iconTex end
        -- (The thin glyph only; the vanilla red X fills its crop already.)
        if winIdx ~= 1 and not iconTex._hdrArt then
            iconTex:ClearAllPoints()
            iconTex:SetSize(btnSize + 2, btnSize + 2)
            iconTex:SetPoint("CENTER", Win.winActionBtn, "CENTER", 0, 0)
        end
        -- Disable + button at max windows / close button when locked
        if winIdx == 1 then
            Win.winActionBtn:HookScript("OnEnter", function(self)
                if #_windows >= MAX_WINDOWS then
                    iconTex:SetAlpha(0.2)
                    CUI.HideWidgetTooltip()
                    CUI.ShowWidgetTooltip(
                        self,
                        CludesUI.Lf("You may only have %1$d windows active", MAX_WINDOWS)
                    )
                end
            end)
        else
            Win.winActionBtn:HookScript("OnEnter", function(self)
                if Win.windowLocked then
                    local ir, ig, ib = IconColor()
                    if not mod.DMHdrHover(iconTex, false, true) then
                        iconTex:SetVertexColor(ir, ig, ib, ICON_ALPHA * 0.5)
                    end
                    CUI.HideWidgetTooltip()
                    CUI.ShowWidgetTooltip(self, "Unlock Window to Close")
                end
            end)
            Win.winActionBtn:HookScript("OnLeave", function()
                if Win.windowLocked then
                    local ir, ig, ib = IconColor()
                    if not mod.DMHdrHover(iconTex, false, true) then
                        iconTex:SetVertexColor(ir, ig, ib, ICON_ALPHA * 0.5)
                    end
                end
            end)
        end
    end
    -- Apply initial close icon dimming if window starts locked
    if winIdx ~= 1 and Win.windowLocked and Win._closeIconTex then
        local ir, ig, ib = IconColor()
        if not mod.DMHdrHover(Win._closeIconTex, false, true) then
            Win._closeIconTex:SetVertexColor(ir, ig, ib, ICON_ALPHA * 0.5)
        end
    end

    -- Reset Data button, left of win action button
    Win.resetBtn = NewHeaderBtn("dm_undo.png", -(btnSize * 3 + btnPad * 4 + 2), "Reset Data", function()
        if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
            C_DamageMeter.ResetAllCombatSessions()
            SetCombatEndTime(0)
            SetCurViewFrozenDur(0)
            for _, wid in ipairs(_windows) do
                wid.Refresh()
            end
        end
    end, "reset")

    -- Ordered list of header buttons for live resize/reposition
    Win.hdrBtns = { Win.settingsBtn, Win.segmentBtn, Win.modeBtn, Win.resetBtn, Win.winActionBtn }
    LayoutHeaderButtons(Win, conf, btnSize)

    -- Truncate the header title so it never runs under the right-side icons; mirrors the icon layout math (N buttons of hdrIconSize spaced by btnPad from the right) rather than relying on GetLeft (can lag a SetPoint)
    function Win.FitTitle()
        local fontStr = Win.titleText
        local full = Win._fullTitle
        if not fontStr or not full then return end
        local cfg = DB()
        local iconSz = mod.DMHdrIconSize(cfg)
        local num = mod.DMHeaderButtonCount(Win, cfg)
        -- Icons hidden until hover occupy no space, so the title gets the whole header instead of truncating against a gap that isn't there
        if Win._hdrIconsShown == false then num = 0 end
        local headerW = widget:GetWidth() or (wdb.width or 300)
        local btnLeft = headerW - (iconSz * num) - (btnPad * num) - 2
        local avail = btnLeft - (6 + (cfg.hdrTextOffX or 0)) - 6
        if avail < 1 then avail = 1 end
        -- The same title in the same room keeps the fit on screen (the header style
        -- pass drops this memo: a font change moves the widths).
        if Win._fitFull == full and Win._fitAvail == avail then return end
        Win._fitFull, Win._fitAvail = full, avail
        fontStr:SetText(full)
        if fontStr:GetStringWidth() <= avail then return end
        local text = full
        while #text > 1 do
            -- Drop one character, not one byte: localised titles are UTF-8 and a mid-codepoint cut renders as garbage
            local i = #text
            while i > 1 do
                local b = string.byte(text, i)
                if b < 0x80 or b >= 0xC0 then break end
                i = i - 1
            end
            text = string.sub(text, 1, i - 1)
            fontStr:SetText(text .. "...")
            if fontStr:GetStringWidth() <= avail then break end
        end
    end

    -- Option: hide header icons until the title bar is hovered
    ApplyHeaderButtonsHoverVisibility(Win, conf)

    -- Snap helpers (X-axis alignment + width matching against other DM windows)
    local SNAP_THRESH = 6

    -- Find the closest other DM window by 2D edge-to-edge distance; optional left/top overrides let drag pass an unsnapped target position
    local function FindClosestWindow(overrideL, overrideT)
        local myL = overrideL or widget:GetLeft() or 0
        local myW2 = widget:GetWidth() or 0
        local myH2 = widget:GetHeight() or 0
        local myT = overrideT or widget:GetTop() or 0
        local myR = myL + myW2
        local myB = myT - myH2
        local closest, closestDist = nil, math.huge
        for _, otherW in ipairs(_windows) do
            if otherW ~= Win and otherW.frame and otherW.frame:IsShown() then
                local oL = otherW.frame:GetLeft() or 0
                local oR = otherW.frame:GetRight() or 0
                local oT = otherW.frame:GetTop() or 0
                local oB = otherW.frame:GetBottom() or 0
                local gapX = 0
                if myR < oL then
                    gapX = oL - myR
                elseif myL > oR then
                    gapX = myL - oR
                end
                local gapY = 0
                if myB > oT then
                    gapY = myB - oT
                elseif myT < oB then
                    gapY = oB - myT
                end
                local dist = math.sqrt(gapX * gapX + gapY * gapY)
                if dist < closestDist then
                    closestDist = dist
                    closest = otherW
                end
            end
        end
        return closest
    end

    local function SnapResizeWidth(newW)
        local near = FindClosestWindow()
        if not near then return newW end
        local oW = near.frame:GetWidth()
        if oW and math.abs(newW - oW) <= SNAP_THRESH then return oW end
        return newW
    end

    local function SnapResizeHeight(newH)
        local near = FindClosestWindow()
        if not near then return newH end
        local oH = near.frame:GetHeight()
        if oH and math.abs(newH - oH) <= SNAP_THRESH then return oH end
        return newH
    end

    -- Header drag (manual, with real-time X-axis snapping)
    header:EnableMouse(true)
    local dragging = false
    local dragStartCX, dragStartCY, dragStartLeft, dragStartTop
    local dragFrame = CreateFrame("Frame")
    dragFrame:Hide()
    dragFrame:SetScript("OnUpdate", function()
        if not dragging then return end
        -- Stop drag if mouse button was released (catches cases where OnMouseUp doesn't fire)
        if not IsMouseButtonDown("LeftButton") then
            dragging = false
            dragFrame:Hide()
            local leftX, topY = widget:GetLeft(), widget:GetTop()
            if leftX and topY then
                if Pix and Pix.Snap then
                    leftX = Pix.Snap(leftX)
                    topY = Pix.Snap(topY)
                end
                wdb.position = { x = leftX, y = topY }
                widget:ClearAllPoints()
                widget:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", leftX, topY)
                -- Manual placement overrides any unlock-mode anchor on this window
                if CludesUIDB and CludesUIDB.unlockAnchors then
                    CludesUIDB.unlockAnchors["EDM_Win" .. Win.idx] = nil
                end
                if CUI.ScheduleSettleReapply then CUI.ScheduleSettleReapply() end
            end
        end
        local curX, curY = GetCursorPosition()
        local es = widget:GetEffectiveScale()
        local newLeft = dragStartLeft + (curX / es - dragStartCX)
        local newTop = dragStartTop + (curY / es - dragStartCY)
        -- Snap to closest window only (use unsnapped target to prevent oscillation)
        local near = not Win.snapDisabled and FindClosestWindow(newLeft, newTop)
        if near then
            local myW = widget:GetWidth()
            local myH = widget:GetHeight()
            local oLeft = near.frame:GetLeft()
            local oRight = near.frame:GetRight()
            local oTop = near.frame:GetTop()
            local oBot = near.frame:GetBottom()
            -- X axis
            if oLeft and oRight then
                local bestDist = SNAP_THRESH + 1
                local snappedLeft = newLeft
                local d1 = math.abs(newLeft - oLeft)
                if d1 < bestDist then
                    bestDist = d1
                    snappedLeft = oLeft
                end
                local d2 = math.abs((newLeft + myW) - oRight)
                if d2 < bestDist then
                    bestDist = d2
                    snappedLeft = oRight - myW
                end
                local d3 = math.abs(newLeft - oRight)
                if d3 < bestDist then
                    bestDist = d3
                    snappedLeft = oRight
                end
                local d4 = math.abs((newLeft + myW) - oLeft)
                if d4 < bestDist then
                    bestDist = d4
                    snappedLeft = oLeft - myW
                end
                if bestDist <= SNAP_THRESH then newLeft = snappedLeft end
            end
            -- Y axis
            if oTop and oBot then
                local bestDistY = SNAP_THRESH + 1
                local snappedTop = newTop
                local d1 = math.abs(newTop - oTop)
                if d1 < bestDistY then
                    bestDistY = d1
                    snappedTop = oTop
                end
                local d2 = math.abs((newTop - myH) - oBot)
                if d2 < bestDistY then
                    bestDistY = d2
                    snappedTop = oBot + myH
                end
                local d3 = math.abs(newTop - oBot)
                if d3 < bestDistY then
                    bestDistY = d3
                    snappedTop = oBot
                end
                local d4 = math.abs((newTop - myH) - oTop)
                if d4 < bestDistY then
                    bestDistY = d4
                    snappedTop = oTop + myH
                end
                if bestDistY <= SNAP_THRESH then newTop = snappedTop end
            end
        end
        -- Snap position to physical pixel grid
        if Pix and Pix.Snap then
            newLeft = Pix.Snap(newLeft)
            newTop = Pix.Snap(newTop)
        end
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", newLeft, newTop)
    end)

    header:SetScript("OnMouseDown", function(_, btnFrame)
        if btnFrame ~= "LeftButton" or Win.windowLocked then return end
        if CUI.InProtectedInstance() then return end
        local curX, curY = GetCursorPosition()
        local es = widget:GetEffectiveScale()
        dragStartCX = curX / es
        dragStartCY = curY / es
        dragStartLeft = widget:GetLeft()
        dragStartTop = widget:GetTop()
        if not dragStartLeft or not dragStartTop then return end
        dragging = true
        dragFrame:Show()
    end)
    header:SetScript("OnMouseUp", function(_, btnFrame)
        -- Right-click on the header toggles the meter-type home screen, matching the window body's right-click behavior
        if btnFrame == "RightButton" then
            if not dragging and Win.ToggleHome then Win.ToggleHome() end
            return
        end
        if btnFrame ~= "LeftButton" or not dragging then return end
        dragging = false
        dragFrame:Hide()
        local leftX, topY = widget:GetLeft(), widget:GetTop()
        if leftX and topY then
            if Pix and Pix.Snap then
                leftX = Pix.Snap(leftX)
                topY = Pix.Snap(topY)
            end
            wdb.position = { x = leftX, y = topY }
            widget:ClearAllPoints()
            widget:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", leftX, topY)
            -- Manual placement overrides any unlock-mode anchor on this window
            if CludesUIDB and CludesUIDB.unlockAnchors then
                CludesUIDB.unlockAnchors["EDM_Win" .. Win.idx] = nil
            end
            -- Reposition elements anchored to this window
            if CUI.ScheduleSettleReapply then CUI.ScheduleSettleReapply() end
        end
    end)

    -- Right-click catcher: opens the home screen on right-click over empty content area below
    -- the header; sits behind the viewport so bar clicks pass through normally.
    local rightClickCatcher = CreateFrame("Button", nil, widget)
    rightClickCatcher:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    rightClickCatcher:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -ci, ci)
    rightClickCatcher:SetFrameLevel(widget:GetFrameLevel() + 1)
    rightClickCatcher:RegisterForClicks("RightButtonUp")
    rightClickCatcher:EnableMouseWheel(false)
    if rightClickCatcher.SetMouseClickEnabled then rightClickCatcher:SetMouseClickEnabled(true) end
    rightClickCatcher:SetScript("OnClick", function() Win.ShowHome() end)

    -- Viewport + scroll
    local viewport = CreateFrame("ScrollFrame", nil, widget)
    viewport:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    viewport:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -ci, ci)
    Win.viewport = viewport

    local contentFrame = CreateFrame("Frame", nil, viewport)
    contentFrame:SetSize(1, 1)
    viewport:SetScrollChild(contentFrame)
    Win.content = contentFrame

    viewport:SetScript("OnSizeChanged", function(self, wid, hgt)
        -- Tracked through guarded pin/unpin resizes too, so "grew" compares against the real last height.
        local grew = hgt and hgt > (Win._vpH or 0)
        Win._vpH = hgt
        -- Before the guard: a profile swap's resize can land inside a sticky pass.
        if wid and wid > 0 then contentFrame:SetWidth(wid) end
        if Win.stickyGuard then return end
        Win.UpdateSticky(nil, Win.visibleCount)
        if Win._decorSync then mod.DMSyncRowDecor(Win) end
        -- A taller viewport reveals rows the last pass skipped; the grip drag queues once on release.
        -- In combat the running ticker fills them (a pin/unpin resize would otherwise double its pass).
        -- (A Threat window, WoW Forever, has no ticker: it fills them in combat too.)
        if grew and not Win.resizing and (not InCombatLockdown() or Win.curDMType == "threat") then
            Win.QueueRepopulate()
        end
    end)

    -- Mouse wheel scrolling (no visual scrollbar)
    local _scrollMax = 0
    local _scrollRefreshPending = false
    -- Rows scrolled or resized into view are filled only by a RefreshUI pass (the ticker
    -- is stopped out of combat): one coalesced pass next frame, through one reused callback.
    local function RunRepopulate()
        _scrollRefreshPending = false
        if Win._lastSession then RefreshUI(Win._lastSession) end
    end
    function Win.QueueRepopulate()
        if _scrollRefreshPending or not Win._lastSession then return end
        _scrollRefreshPending = true
        C_Timer.After(0, RunRepopulate)
    end
    viewport:EnableMouseWheel(true)
    viewport:SetScript("OnMouseWheel", function(_, delta)
        local cfg = DB()
        local _, _, stride =
            mod._RowMetrics(cfg.barHeight or 18, cfg.barSpacing or 2, widget:GetEffectiveScale())
        local current = viewport:GetVerticalScroll() or 0
        -- Return to the row grid after the bottom clamp splits a row.
        local target = (math.floor(current / stride + 0.5) - delta * 2) * stride
        local newVal = math.max(0, math.min(_scrollMax, target))
        viewport:SetVerticalScroll(newVal)
        Win.UpdateSticky(nil, Win.visibleCount)
        if Win._decorSync then mod.DMSyncRowDecor(Win) end
        Win.QueueRepopulate()
    end)

    -- Bar pool
    Win.rowPool = {}
    for i = 1, BAR_POOL_SIZE do
        Win.rowPool[i] = MakeRow(contentFrame)
    end

    -- Sticky player bar
    Win.stickyPlayer = MakeRow(widget)
    Win.stickyPlayer.row:SetFrameLevel(widget:GetFrameLevel() + 8)
    Win.stickyPlayer.row:Hide()

    local onePx = (Pix and Pix.mult) or 1
    Win.stickySep = CreateFrame("Frame", nil, widget)
    Win.stickySep:SetHeight(onePx)
    Win.stickySep:SetFrameLevel(widget:GetFrameLevel() + 10)
    local sepTex = Win.stickySep:CreateTexture(nil, "OVERLAY", nil, 6)
    sepTex:SetAllPoints()
    sepTex:SetColorTexture(0, 0, 0, 1)
    Win.stickySep:Hide()

    -- Source window
    Win.sourceFrame = CreateFrame("Frame", nil, widget)
    Win.sourceFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    Win.sourceFrame:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -ci, ci)
    Win.sourceFrame:SetFrameLevel(widget:GetFrameLevel() + 20)
    Win.sourceFrame:EnableMouse(true)
    Win.sourceFrame:Hide()
    Win.sourceFrame._bg = Win.sourceFrame:CreateTexture(nil, "BACKGROUND")
    Win.sourceFrame._bg:SetAllPoints()
    mod.DMPaintWindowBg(
        Win.sourceFrame._bg,
        conf.bgR or 0,
        conf.bgG or 0,
        conf.bgB or 0,
        conf.bgAlpha or 0.75,
        nil,
        conf.bgTexture
    )

    Win.srcViewport = CreateFrame("ScrollFrame", nil, Win.sourceFrame)
    Win.srcViewport:SetAllPoints()
    Win.srcContent = CreateFrame("Frame", nil, Win.srcViewport)
    Win.srcContent:SetSize(1, 1)
    Win.srcViewport:SetScrollChild(Win.srcContent)
    Win.srcViewport:SetScript("OnSizeChanged", function(_, wid) Win.srcContent:SetWidth(wid) end)

    -- Mouse wheel scrolling for spell breakdown
    local _srcScrollMax = 0
    Win.srcViewport:EnableMouseWheel(true)
    Win.srcViewport:SetScript("OnMouseWheel", function(_, delta)
        local cfg = DB()
        local _, _, step =
            mod._RowMetrics(cfg.barHeight or 18, cfg.barSpacing or 2, widget:GetEffectiveScale())
        step = step * 2
        local current = Win.srcViewport:GetVerticalScroll() or 0
        Win.srcViewport:SetVerticalScroll(math.max(0, math.min(_srcScrollMax, current - delta * step)))
    end)

    Win.sourceFrame:SetScript("OnMouseDown", function() Win.CloseSource() end)

    Win.spellPool = nil -- lazy-created on first OpenSource
    local function EnsureSpellPool()
        if Win.spellPool then return end
        Win.spellPool = {}
        for i = 1, BAR_POOL_SIZE do
            Win.spellPool[i] = MakeSpellRow(Win.srcContent)
        end
    end

    -- Resize grip
    Win.resizeGrip = CreateFrame("Button", nil, widget)
    Win.resizeGrip:SetSize(18, 18)
    Win.resizeGrip:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -2, 2)
    Win.resizeGrip:SetFrameLevel(widget:GetFrameLevel() + 15)
    local gripTex = Win.resizeGrip:CreateTexture(nil, "ARTWORK")
    gripTex:SetAllPoints()
    gripTex:SetTexture(RESIZE_ICON)
    gripTex:SetDesaturated(true)
    gripTex:SetVertexColor(1, 1, 1)
    Win.resizeGrip:EnableMouse(true)
    Win.resizeGrip:SetAlpha(0)
    Win.resizeGrip:SetScript("OnEnter", function(self)
        if not Win.windowLocked then self:SetAlpha(0.7) end
    end)
    Win.resizeGrip:SetScript(
        "OnLeave",
        function(self) self:SetAlpha((Win.isHovered and not Win.windowLocked) and 0.3 or 0) end
    )

    -- Lock icon (shows/hides with resize grip, click toggles lock state)
    Win.lockBtn = CreateFrame("Button", nil, widget)
    Win.lockBtn:SetSize(13, 17)
    Win.lockBtn:SetFrameLevel(widget:GetFrameLevel() + 16)
    Win.lockBtn:EnableMouse(true)
    Win.lockBtn:SetAlpha(0)
    local lockTex = Win.lockBtn:CreateTexture(nil, "ARTWORK")
    lockTex:SetAllPoints()
    lockTex:SetDesaturated(true)
    lockTex:SetVertexColor(1, 1, 1)
    -- The vanilla lock art is a square button: give it a square to sit in.
    if mod.DMHdrArt("locked") then Win.lockBtn:SetSize(18, 18) end

    local function PaintLockIcon()
        if Win.windowLocked then
            if not mod.DMPaintHdrArt(lockTex, "locked") then lockTex:SetTexture(MEDIA .. "dm_locked.png") end
            Win.lockBtn:ClearAllPoints()
            Win.lockBtn:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -4, 4)
        else
            if not mod.DMPaintHdrArt(lockTex, "unlocked") then
                lockTex:SetTexture(MEDIA .. "dm_unlocked.png")
            end
            Win.lockBtn:ClearAllPoints()
            Win.lockBtn:SetPoint("RIGHT", Win.resizeGrip, "LEFT", -2, 0)
        end
        -- Dim close icon when locked (non-window-1 only)
        if winIdx ~= 1 and Win._closeIconTex then
            local ir, ig, ib = IconColor()
            if not mod.DMHdrHover(Win._closeIconTex, false, Win.windowLocked) then
                Win._closeIconTex:SetVertexColor(
                    ir,
                    ig,
                    ib,
                    Win.windowLocked and (ICON_ALPHA * 0.5) or ICON_ALPHA
                )
            end
        end
    end
    PaintLockIcon()

    Win.lockBtn:SetScript("OnEnter", function(self)
        self:SetAlpha(0.7)
        CUI.ShowWidgetTooltip(self, Win.windowLocked and "Locked" or "Unlocked")
    end)
    Win.lockBtn:SetScript("OnLeave", function(self)
        self:SetAlpha(Win.isHovered and 0.3 or 0)
        CUI.HideWidgetTooltip()
    end)
    Win.lockBtn:SetScript("OnClick", function()
        Win.windowLocked = not Win.windowLocked
        wdb.locked = Win.windowLocked
        PaintLockIcon()
        if Win.windowLocked then
            Win.resizeGrip:SetAlpha(0)
            Win.lockBtn:SetAlpha(Win.isHovered and 0.3 or 0)
        else
            local a = Win.isHovered and 0.3 or 0
            Win.resizeGrip:SetAlpha(a)
            Win.lockBtn:SetAlpha(a)
        end
        CUI.HideWidgetTooltip()
        CUI.ShowWidgetTooltip(Win.lockBtn, Win.windowLocked and "Locked" or "Unlocked")
    end)
    Win._updateLockIcon = PaintLockIcon

    local resizeStartX, resizeStartY, resizeStartW, resizeStartH
    local resizeAnchorLeft, resizeAnchorTop -- pinned TOPLEFT during resize
    local resizeFrame = CreateFrame("Frame")
    resizeFrame:Hide()
    local resizeAxis = nil -- nil = free, "w" = width only, "h" = height only
    local resizeShiftWas = false
    resizeFrame:SetScript("OnUpdate", function()
        if not Win.resizing then return end
        local curX, curY = GetCursorPosition()
        local es = widget:GetEffectiveScale()
        local dx = curX / es - resizeStartX
        local dy = resizeStartY - curY / es
        local shiftDown = IsShiftKeyDown()
        local newW, newH
        if shiftDown then
            if not resizeShiftWas then resizeAxis = math.abs(dx) >= math.abs(dy) and "w" or "h" end
            if resizeAxis == "w" then
                newW = math.max(MIN_W, resizeStartW + dx)
                newH = math.max(MIN_H, resizeStartH)
            else
                newW = math.max(MIN_W, resizeStartW)
                newH = math.max(MIN_H, resizeStartH + dy)
            end
        else
            resizeAxis = nil
            newW = math.max(MIN_W, resizeStartW + dx)
            newH = math.max(MIN_H, resizeStartH + dy)
        end
        -- Snap width/height to other windows
        if not Win.snapDisabled then
            newW = SnapResizeWidth(newW)
            newH = SnapResizeHeight(newH)
        end
        -- Cap size so frame can't extend past screen edges from pinned TOPLEFT
        local screenW = UIParent:GetRight() or 0
        local screenB = UIParent:GetBottom() or 0
        local maxW = screenW - resizeAnchorLeft
        local maxH = resizeAnchorTop - screenB
        if maxW > MIN_W then newW = math.min(newW, maxW) end
        if maxH > MIN_H then newH = math.min(newH, maxH) end
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", resizeAnchorLeft, resizeAnchorTop)
        widget:SetSize(newW, newH)
        resizeShiftWas = shiftDown
    end)

    Win.resizeGrip:SetScript("OnMouseDown", function(_, btnFrame)
        if btnFrame ~= "LeftButton" or Win.windowLocked then return end
        if CUI.InProtectedInstance() then return end
        local leftX, topY = widget:GetLeft(), widget:GetTop()
        if leftX and topY then
            widget:ClearAllPoints()
            widget:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", leftX, topY)
            -- Convert the STORED position to match the pin immediately, not
            -- just on mouse-up. wdb.position is point-format whenever unlock
            -- mode saved it (an imported profile is all point-format), and
            -- ApplyWinPosition re-applies that as SetPoint(pos.point, ...) --
            -- a different anchor from the TOPLEFT pin above. Any re-apply that
            -- lands mid-drag therefore yanks the frame back to its old anchor,
            -- which is the resize "glitch": random, because it depends on
            -- whether a refresh happens while the mouse is down. A window whose
            -- position is already legacy format never showed it, since that
            -- re-applies to the same corner the pin uses.
            if wdb.position and wdb.position.point then wdb.position = { x = leftX, y = topY } end
        end
        resizeAnchorLeft = leftX
        resizeAnchorTop = topY
        local curX, curY = GetCursorPosition()
        local es = widget:GetEffectiveScale()
        resizeStartX = curX / es
        resizeStartY = curY / es
        resizeStartW = widget:GetWidth()
        resizeStartH = widget:GetHeight()
        Win.resizing = true
        resizeFrame:Show()
    end)
    Win.resizeGrip:SetScript("OnMouseUp", function(_, btnFrame)
        if btnFrame ~= "LeftButton" or not Win.resizing then return end
        Win.resizing = false
        resizeFrame:Hide()
        wdb.width = math.floor(widget:GetWidth() + 0.5)
        wdb.height = math.floor(widget:GetHeight() + 0.5)
        -- Resize pins the TOPLEFT corner, so a point-based position from unlock mode (e.g.
        -- CENTER-anchored) no longer describes this spot; re-save in TOPLEFT drag format to match
        if wdb.position and wdb.position.point then
            local leftX, topY = widget:GetLeft(), widget:GetTop()
            if leftX and topY then wdb.position = { x = leftX, y = topY } end
        end
        Win.UpdateSticky(nil, Win.visibleCount)
        if Win._decorSync then mod.DMSyncRowDecor(Win) end
        Win.QueueRepopulate()
        -- Refresh home screen card widths one frame after resize
        if homeFrame and homeFrame:IsShown() then
            C_Timer.After(0, function()
                if RefreshHome then RefreshHome() end
            end)
        end
    end)

    -- Hover fade (scrollbar + resize grip)
    do
        local fadeSpeed = 1 / 0.12
        local fadeAlpha = 0
        local fadeTarget = 0
        local fadeFrame2 = CreateFrame("Frame")
        fadeFrame2:Hide()
        fadeFrame2:SetScript("OnUpdate", function(self, elapsed)
            local step = fadeSpeed * elapsed
            fadeAlpha = fadeTarget > fadeAlpha and math.min(fadeTarget, fadeAlpha + step)
                or math.max(fadeTarget, fadeAlpha - step)
            if math.abs(fadeAlpha - fadeTarget) < 0.001 then fadeAlpha = fadeTarget end
            if Win.resizeGrip and not Win.windowLocked and not Win.resizeGrip:IsMouseOver() then
                Win.resizeGrip:SetAlpha(fadeAlpha * 0.3)
            end
            if Win.lockBtn and not Win.lockBtn:IsMouseOver() then Win.lockBtn:SetAlpha(fadeAlpha * 0.3) end
            if fadeAlpha == fadeTarget then self:Hide() end
        end)
        local function FadeIn()
            fadeTarget = 1
            fadeFrame2:Show()
        end
        local function FadeOut()
            fadeTarget = 0
            fadeFrame2:Show()
        end
        local wasOver = false
        local hoverTicker -- forward ref
        local function HoverPoll()
            local over = widget:IsMouseOver()
                or (Win.resizeGrip and Win.resizeGrip:IsMouseOver())
                or (Win.lockBtn and Win.lockBtn:IsMouseOver())
            if over and not wasOver then
                wasOver = true
                Win.isHovered = true
                FadeIn()
            elseif not over and wasOver then
                wasOver = false
                Win.isHovered = false
                FadeOut()
                -- Stop polling until next OnEnter
                if hoverTicker then
                    hoverTicker:Cancel()
                    hoverTicker = nil
                end
            end
        end
        local function PollHover()
            if hoverTicker then return end
            hoverTicker = C_Timer.NewTicker(0.1, HoverPoll)
        end
        -- OnEnter on the main frame starts the poll
        widget:HookScript("OnEnter", PollHover)
        -- Also start from children that sit above the frame
        header:HookScript("OnEnter", PollHover)
        viewport:HookScript("OnEnter", PollHover)
        rightClickCatcher:HookScript("OnEnter", PollHover)
        Win.resizeGrip:HookScript("OnEnter", PollHover)
        Win.lockBtn:HookScript("OnEnter", PollHover)
        Win._startHoverPoll = PollHover
        -- Ends any hover at once (W.Park): the poll and the fade stop, and the grip and lock go to alpha 0.
        Win._endHover = function()
            if hoverTicker then
                hoverTicker:Cancel()
                hoverTicker = nil
            end
            wasOver = false
            Win.isHovered = false
            fadeAlpha, fadeTarget = 0, 0
            fadeFrame2:Hide()
            Win.resizeGrip:SetAlpha(0)
            Win.lockBtn:SetAlpha(0)
        end
        -- Hook bar rows so entering from the content area starts the poll
        for _, barFrame in ipairs(Win.rowPool) do
            barFrame.row:HookScript("OnEnter", PollHover)
        end
        if Win.stickyPlayer then Win.stickyPlayer.row:HookScript("OnEnter", PollHover) end
    end

    -- Per-window functions
    local function ResetScrollAnchors()
        if not viewport or not header or not widget then return end
        Win.stickyGuard = true
        -- ci: the classic box's inset (0 on every other look), as at creation.
        viewport:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
        viewport:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -ci, ci)
        -- Clamp scroll
        if contentFrame then
            local viewH = widget:GetHeight() - GetHeaderH() - 2 * ci
            if viewH < 1 then viewH = 1 end
            local totalH = contentFrame:GetHeight()
            local maxScr = math.max(0, totalH - viewH)
            _scrollMax = maxScr
            local current = viewport:GetVerticalScroll()
            if current > maxScr then viewport:SetVerticalScroll(maxScr) end
        end
        Win.stickyGuard = false
    end

    local function RecalcViewport(dataCount)
        if not viewport or not contentFrame then return end
        local cfg = DB()
        local _, _, stride =
            mod._RowMetrics(cfg.barHeight or 18, cfg.barSpacing or 2, widget:GetEffectiveScale())
        local totalH = dataCount * stride
        contentFrame:SetHeight(math.max(10, totalH))
        local viewH = viewport:GetHeight()
        if viewH < 1 then viewH = 1 end
        _scrollMax = math.max(0, totalH - viewH)
        local current = viewport:GetVerticalScroll() or 0
        if current > _scrollMax then viewport:SetVerticalScroll(_scrollMax) end
    end

    function Win.UpdateSticky(sources, visibleCount)
        if Win.stickyGuard then return end
        -- Don't show sticky while home screen or source window is open
        if (homeFrame and homeFrame:IsShown()) or Win.sourceOpen then
            Win.stickyPlayer.row:Hide()
            Win.stickySep:Hide()
            return
        end
        if sources then Win.cachedSources = sources end
        sources = Win.cachedSources
        if not Win.stickyPlayer or not Win.stickySep then return end
        local cfg = DB()
        -- (A Threat list, WoW Forever, pins no row.)
        if
            cfg.showPinnedSelf == false
            or not _playerGUID
            or not sources
            or #sources == 0
            or Win.curDMType == "threat"
        then
            Win.stickyPlayer.row:Hide()
            Win.stickySep:Hide()
            ResetScrollAnchors()
            Win.stickyAtTop = false
            return
        end
        local playerIdx
        for i, source in ipairs(sources) do
            if source.isLocalPlayer then
                playerIdx = i
                break
            end
        end
        if not playerIdx then
            Win.stickyPlayer.row:Hide()
            Win.stickySep:Hide()
            ResetScrollAnchors()
            Win.stickyAtTop = false
            return
        end
        local barH, _, stride, pxMult =
            mod._RowMetrics(cfg.barHeight or 18, cfg.barSpacing or 2, widget:GetEffectiveScale())
        local scrollVal = viewport:GetVerticalScroll() or 0
        local fullViewH = widget:GetHeight() - GetHeaderH() - 2 * ci
        if fullViewH < 1 then fullViewH = 1 end
        local barTop = (playerIdx - 1) * stride
        local barBot = barTop + barH
        -- Unpin the instant the player bar is fully within the viewport (1px tolerance for float drift)
        if barTop >= scrollVal - 1 and barBot <= scrollVal + fullViewH + 1 then
            Win.stickyPlayer.row:Hide()
            Win.stickySep:Hide()
            ResetScrollAnchors()
            Win.stickyAtTop = false
            return
        end
        local pinTop = (barTop < scrollVal)
        Win.stickyAtTop = pinTop
        local pinnedH = barH + pxMult
        Win.stickyPlayer.row:ClearAllPoints()
        Win.stickySep:ClearAllPoints()
        Win.stickySep:SetHeight(pxMult)
        if pinTop then
            Win.stickyPlayer.row:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
            Win.stickyPlayer.row:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
            Win.stickySep:SetPoint("TOPLEFT", Win.stickyPlayer.row, "BOTTOMLEFT", 0, 0)
            Win.stickySep:SetPoint("TOPRIGHT", Win.stickyPlayer.row, "BOTTOMRIGHT", 0, 0)
        else
            Win.stickyPlayer.row:SetPoint("BOTTOMLEFT", widget, "BOTTOMLEFT", ci, ci)
            Win.stickyPlayer.row:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -ci, ci)
            Win.stickySep:SetPoint("BOTTOMLEFT", Win.stickyPlayer.row, "TOPLEFT", 0, 0)
            Win.stickySep:SetPoint("BOTTOMRIGHT", Win.stickyPlayer.row, "TOPRIGHT", 0, 0)
        end
        Win.stickyGuard = true
        if pinTop then
            viewport:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -pinnedH)
            viewport:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -ci, ci)
        else
            viewport:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
            viewport:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -ci, pinnedH + ci)
        end
        -- Clamp scroll after viewport resize
        local newViewH = viewport:GetHeight()
        if newViewH and newViewH > 0 then
            -- The content holds at most the pool, as RecalcViewport sizes it.
            local totalH = math.min(#sources, BAR_POOL_SIZE) * stride
            local maxScr = math.max(0, totalH - newViewH)
            _scrollMax = maxScr
            local current = viewport:GetVerticalScroll()
            if current > maxScr then viewport:SetVerticalScroll(maxScr) end
        end
        Win.stickyGuard = false
        -- Fill sticky bar (cached -- only SetValue/SetText per tick)
        local isDeaths = (Win.curDMType == Enum.DamageMeterType.Deaths)
        local isCount = (
            Win.curDMType == Enum.DamageMeterType.Interrupts
            or Win.curDMType == Enum.DamageMeterType.Dispels
        )
        local source = sources[playerIdx]
        local maxAmt = isDeaths and 1 or (sources[1] and sources[1].totalAmount or 1)
        local barFrame = Win.stickyPlayer
        local leftFS = cfg.leftFontSize or cfg.fontSize or 11
        local rightFS = cfg.rightFontSize or cfg.fontSize or 11
        local iconStyle = cfg.iconStyle or "spec"
        local showIcon = iconStyle ~= "none"
        local showClassColor = cfg.showClassColor ~= false
        local texPath, texKey = GetBarTexturePath()
        -- Layout cache: only rebuild on settings change (iconStyle, as the row key: a style switch re-resolves the icon)
        local stickyCacheKey = leftFS
            .. "|"
            .. rightFS
            .. "|"
            .. texPath
            .. "|"
            .. iconStyle
            .. "|"
            .. tostring(showClassColor)
            .. "|"
            .. barH
            .. "|"
            .. tostring(cfg.classIconZoom)
            .. "|"
            .. tostring(cfg.barFillAlpha)
        if (cfg.spriteIconZoom or 0) ~= 0 then
            stickyCacheKey = stickyCacheKey .. "|" .. cfg.spriteIconZoom
        end
        if stickyCacheKey ~= Win._stickyCacheKey then
            Win._stickyCacheKey = stickyCacheKey
            barFrame.row:SetHeight(barH)
            barFrame.fill:ClearAllPoints()
            barFrame.fill:SetHeight(barH)
            ApplyBarTexture(barFrame.fill, texPath, texKey)
            barFrame.fill:SetAlpha(cfg.barFillAlpha or 1)
            SetDMFont(barFrame.pos, leftFS)
            SetDMFont(barFrame.label, leftFS)
            SetDMFont(barFrame.amount, rightFS)
            barFrame.label:SetWidth(math.max(20, (widget:GetWidth() or 200) * 0.60))
            Win._stickyClassCache = false
            Win._stickySpecCache = nil -- false: never a classFilename, forces the icon/colour pass
        end
        barFrame.row:Show()
        -- Icon + color: only when class changes
        -- Same spec-aware memo as the row loop below: the sticky bar is
        -- re-pointed at whatever source holds the player's rank.
        local class = source.classFilename
        local specIcon = source.specIconID
        if issecretvalue(specIcon) then specIcon = nil end -- WoW Forever 1.60.1: always secret
        if class ~= Win._stickyClassCache or specIcon ~= Win._stickySpecCache then
            Win._stickyClassCache = class
            Win._stickySpecCache = specIcon
            local iconOffset = showIcon and ResolveIcon(source, barFrame.classIcon, barH) or 0
            if not showIcon then barFrame.classIcon:Hide() end
            if barFrame._iconBorderFrame then
                barFrame._iconBorderFrame:SetShown(
                    cfg.customIconBorder and (cfg.iconBorderSize or 0) > 0 and barFrame.classIcon:IsShown()
                )
            end
            barFrame.fill:SetPoint("TOPLEFT", barFrame.row, "TOPLEFT", iconOffset, 0)
            barFrame.fill:SetPoint("TOPRIGHT", barFrame.row, "TOPRIGHT", 0, 0)
            if showClassColor then
                local classColor = class and RAID_CLASS_COLORS[class] and CUI.GetClassColor(class)
                if classColor then
                    barFrame.fill:SetStatusBarColor(classColor.r, classColor.g, classColor.b)
                elseif Win.curDMType == Enum.DamageMeterType.EnemyDamageTaken then
                    barFrame.fill:SetStatusBarColor(0xDD / 255, 0x31 / 255, 0x31 / 255)
                else
                    barFrame.fill:SetStatusBarColor(0.5, 0.5, 0.5)
                end
            end
            -- Repaint class-colored background for the new class (no-op when off); bar._class set here so ApplyBg reads the current class
            barFrame._class = class
            if cfg.barBgUseClassColor then barFrame.ApplyBg() end
        end
        -- Accent / custom fill: outside the class memo (as the rows paint it), so Use Accent,
        -- Custom Color and a live accent change reach the pinned row.
        if not showClassColor then
            if cfg.barColorUseAccent ~= false then
                local ar2, ag2, ab2 = GetAccentRGB()
                barFrame.fill:SetStatusBarColor(ar2, ag2, ab2)
            else
                local bc = cfg.barColor
                barFrame.fill:SetStatusBarColor(bc and bc.r or 0.35, bc and bc.g or 0.55, bc and bc.b or 0.8)
            end
        end
        -- Per-tick: value + text only
        if isDeaths then
            barFrame.fill:SetMinMaxValues(0, 1)
            barFrame.fill:SetValue(1)
        else
            barFrame.fill:SetMinMaxValues(0, maxAmt)
            barFrame.fill:SetValue(source.totalAmount or 0)
        end
        -- Rank: only when position changes
        local hideNums = cfg.hideNumbers
        if hideNums then
            barFrame.pos:SetText("")
            Win._stickyRankCache = nil -- un-hiding repaints the rank
        elseif playerIdx ~= Win._stickyRankCache then
            Win._stickyRankCache = playerIdx
            barFrame.pos:SetText(RANK_STRINGS[playerIdx] or (playerIdx .. "."))
        end
        -- Name: only when source name changes (guard secret values)
        local srcName = source.name
        if issecretvalue and issecretvalue(srcName) then
            barFrame.label:SetText(StripRealm(srcName, source))
            Win._stickyNameCache = nil
        elseif srcName ~= Win._stickyNameCache then
            Win._stickyNameCache = srcName
            barFrame.label:SetText(StripRealm(srcName, source))
        end
        if isDeaths then
            local isOverall = (not Win.curSessionID and Win.curSession == Enum.DamageMeterSessionType.Overall)
            barFrame.amount:SetText(
                isOverall and ""
                    or mod._DeathTimeText(
                        source,
                        not Win.curSessionID and Win.curSession == Enum.DamageMeterSessionType.Current
                    )
            )
        elseif isCount then
            barFrame.amount:SetText(AbbrevNumber(source.totalAmount))
        else
            barFrame.amount:SetText(
                FormatBarValue(source.totalAmount, source.amountPerSecond, cfg.numberFormat or 2)
            )
        end
        if cfg.rightTextUseThreatGradient then
            if not Win._valueGradientRange then mod.DMPrepareValueGradient(Win, sources, #sources) end
            mod.DMPaintValueGradient(barFrame, Win, source, playerIdx)
            barFrame._valueGradientActive = true
        elseif barFrame._valueGradientActive then
            barFrame._valueGradientActive, barFrame._gradT = nil, nil
            local color = cfg.rightTextUseClassColor and class and CUI.GetClassColor(class)
                or cfg.rightTextColor
            barFrame.amount:SetTextColor(
                color and color.r or 1,
                color and color.g or 1,
                color and color.b or 1
            )
        end
        barFrame._src = source
        barFrame._srcGUID = source.sourceGUID
        barFrame._class = class
        Win.stickySep:Show()
        if cfg.barSeparators or cfg.iconSeparator or cfg.showPlayerMarker or Win._decorSync then
            mod.DMApplyRowDecor(barFrame, Win, source, pinTop and 0 or -1)
        end
    end

    RefreshUI = function(session)
        if not widget then return end
        -- Hidden (a deferred or repopulate pass landing after a hide): no paint. The
        -- OnShow catch-up refetches, so the skipped session never reaches the screen.
        if not widget:IsVisible() then
            Win._refreshPending = true
            return
        end
        Win._lastSession = session -- cache for scroll-triggered refresh

        -- Populate rows
        local count = 0
        if session and session.combatSources then
            local sources = session.combatSources
            local cfg = DB()
            local barH, barSp, stride =
                mod._RowMetrics(cfg.barHeight or 18, cfg.barSpacing or 2, widget:GetEffectiveScale())
            local rowDecor = cfg.barSeparators or cfg.iconSeparator or cfg.showPlayerMarker or Win._decorSync
            local leftFS = cfg.leftFontSize or cfg.fontSize or 11
            local rightFS = cfg.rightFontSize or cfg.fontSize or 11
            local fontSize = leftFS -- compat for cacheKey
            local showIcon = (cfg.iconStyle or "spec") ~= "none"
            local showClassColor = cfg.showClassColor ~= false
            local texPath, texKey = GetBarTexturePath()
            local rowWidth = viewport:GetWidth() or 200
            local labelMaxW = math.max(20, rowWidth * 0.60)
            local isDeaths = (Win.curDMType == Enum.DamageMeterType.Deaths)
            local isCount = (
                Win.curDMType == Enum.DamageMeterType.Interrupts
                or Win.curDMType == Enum.DamageMeterType.Dispels
            )
            -- WoW Forever's Threat rows carry their rank, value text and highlight colour.
            local isThreat = (Win.curDMType == "threat")
            -- Deaths: reverse to chronological (API returns most recent first) and filter feign
            -- deaths; CleanupFeignCache runs first so real deaths after Feign Death aren't hidden by the cached spell 5384 GUID
            if isDeaths then
                CleanupFeignCache()
                local rev = {}
                for ri = #sources, 1, -1 do
                    local cfg = sources[ri]
                    local rid = cfg.deathRecapID
                    local sg = cfg.sourceGUID
                    -- _feignDeathGUIDs[secret] throws ("cannot be indexed with secret keys"), so only
                    -- consult the cache for a plain-string GUID; secret-GUID rows fall back to the deathRecapID-only filter
                    local sgOk = sg and (not issecretvalue or not issecretvalue(sg))
                    if
                        not (issecretvalue and issecretvalue(rid))
                        and rid
                        and rid > 0
                        and not (sgOk and _feignDeathGUIDs[sg])
                    then
                        rev[#rev + 1] = cfg
                    end
                end
                sources = rev
            end
            local maxAmt = isDeaths and 1 or (sources[1] and sources[1].totalAmount or 1)
            count = math.min(#sources, BAR_POOL_SIZE)
            if cfg.rightTextUseThreatGradient then mod.DMPrepareValueGradient(Win, sources, #sources) end
            -- Before the visible range below: it must read this segment's clamped scroll and pinned viewport.
            RecalcViewport(count)
            Win.UpdateSticky(sources, count)
            -- Cache key: detects settings changes that require full bar rebuild
            local iconStyle = cfg.iconStyle or "spec"
            local cacheKey = leftFS
                .. "|"
                .. rightFS
                .. "|"
                .. texPath
                .. "|"
                .. iconStyle
                .. "|"
                .. tostring(showClassColor)
                .. "|"
                .. tostring(cfg.barColorUseAccent)
                .. "|"
                .. barH
                .. "|"
                .. barSp
                .. "|"
                .. tostring(cfg.hideNumbers)
                .. "|"
                .. tostring(cfg.leftTextUseClassColor)
                .. "|"
                .. tostring(cfg.rightTextUseClassColor)
                .. "|"
                .. tostring(cfg.barFillAlpha)
                .. "|"
                .. tostring(cfg.classIconZoom)
            if (cfg.spriteIconZoom or 0) ~= 0 or cfg.rightTextUseThreatGradient then
                cacheKey = cacheKey
                    .. "|"
                    .. tostring(cfg.spriteIconZoom)
                    .. "|"
                    .. tostring(cfg.rightTextUseThreatGradient)
            end
            local fullRebuild = (cacheKey ~= Win._barCacheKey)
            if fullRebuild then Win._barCacheKey = cacheKey end

            local numFmt = cfg.numberFormat or 2
            local isSecret = issecretvalue and true or false

            -- Visible range calculation
            local scrollOff = viewport:GetVerticalScroll() or 0
            local viewH = viewport:GetHeight() or 200
            -- Unresolved rect (first pass after build): fill every row once. A squeezed
            -- but resolved viewport keeps its real height, or it would fill the pool every tick.
            if viewH <= 0 and not viewport:IsRectValid() then viewH = count * stride end
            local visFirst = math.floor(scrollOff / stride) + 1
            local visLast = math.min(count, math.ceil((scrollOff + viewH) / stride))

            for i = 1, BAR_POOL_SIZE do
                local barFrame = Win.rowPool[i]
                if i <= count then
                    local source = sources[i]
                    if not barFrame.row:IsShown() then barFrame.row:Show() end

                    -- Layout + appearance: only on settings change or bar reuse
                    if fullRebuild or barFrame._cachedSlot ~= i then
                        barFrame._cachedSlot = i
                        barFrame.row:ClearAllPoints()
                        local yOff = -((i - 1) * stride)
                        barFrame.row:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, yOff)
                        barFrame.row:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", 0, yOff)
                        barFrame.row:SetHeight(barH)
                        barFrame.fill:ClearAllPoints()
                        barFrame.fill:SetHeight(barH)
                        ApplyBarTexture(barFrame.fill, texPath, texKey)
                        barFrame.fill:SetAlpha(cfg.barFillAlpha or 1)
                        SetDMFont(barFrame.pos, leftFS)
                        SetDMFont(barFrame.label, leftFS)
                        SetDMFont(barFrame.amount, rightFS)
                        barFrame.label:SetWidth(labelMaxW)
                        if cfg.hideNumbers then
                            barFrame.pos:SetText("")
                        else
                            barFrame.pos:SetText(RANK_STRINGS[i] or (i .. "."))
                        end
                        -- false: never a classFilename, so the next visible pass always re-seats the fill cleared above
                        barFrame._cachedClass = false
                        barFrame._cachedSpecIcon = nil
                        barFrame._cachedColorClass = false
                        barFrame._cachedRank = nil
                        barFrame._cachedThreatColor = nil
                        barFrame._gradT = nil
                    end

                    -- Per-tick content: only for visible bars
                    if i >= visFirst and i <= visLast then
                        -- Icon: only when class changes
                        -- Icon: only when the icon's own inputs change. The
                        -- memo must include the SPEC, not just the class: bars
                        -- are recycled by rank, so a swap between same-class
                        -- players of different specs left classFile unchanged
                        -- and the row kept the previous player's spec icon.
                        local class = source.classFilename
                        local specIcon = source.specIconID
                        if issecretvalue(specIcon) then specIcon = nil end -- WoW Forever 1.60.1: always secret
                        if class ~= barFrame._cachedClass or specIcon ~= barFrame._cachedSpecIcon then
                            barFrame._cachedClass = class
                            barFrame._cachedSpecIcon = specIcon
                            local iconOffset = showIcon and ResolveIcon(source, barFrame.classIcon, barH) or 0
                            if not showIcon then barFrame.classIcon:Hide() end
                            if barFrame._iconBorderFrame then
                                barFrame._iconBorderFrame:SetShown(
                                    cfg.customIconBorder
                                        and (cfg.iconBorderSize or 0) > 0
                                        and barFrame.classIcon:IsShown()
                                )
                            end
                            barFrame.fill:SetPoint("TOPLEFT", barFrame.row, "TOPLEFT", iconOffset, 0)
                            barFrame.fill:SetPoint("TOPRIGHT", barFrame.row, "TOPRIGHT", 0, 0)
                            barFrame._cachedColorClass = false
                            -- Repaint class-colored background for the new class (no-op when off); bar._class set here so ApplyBg reads the current class
                            barFrame._class = class
                            if cfg.barBgUseClassColor then barFrame.ApplyBg() end
                        end

                        -- Fill value
                        if isDeaths then
                            barFrame.fill:SetMinMaxValues(0, 1)
                            barFrame.fill:SetValue(1)
                        else
                            barFrame.fill:SetMinMaxValues(0, maxAmt)
                            barFrame.fill:SetValue(source.totalAmount or 0)
                        end

                        -- Threat: the pull line takes no rank, so ranks move with it
                        if isThreat and not cfg.hideNumbers and barFrame._cachedRank ~= source.rankText then
                            barFrame._cachedRank = source.rankText
                            barFrame.pos:SetText(source.rankText)
                        end

                        -- Color (a Threat row's highlight wins; false makes the
                        -- next plain row repaint its own colour, which drops the
                        -- highlight memo)
                        local threatColor = isThreat and source.threatColor
                        if threatColor then
                            if barFrame._cachedThreatColor ~= threatColor then
                                barFrame._cachedThreatColor = threatColor
                                barFrame.fill:SetStatusBarColor(threatColor.r, threatColor.g, threatColor.b)
                            end
                            barFrame._cachedColorClass = false
                        elseif showClassColor then
                            if class ~= barFrame._cachedColorClass then
                                barFrame._cachedColorClass = class
                                barFrame._cachedThreatColor = nil
                                local classColor = class and RAID_CLASS_COLORS[class] and CUI.GetClassColor(class)
                                if classColor then
                                    barFrame.fill:SetStatusBarColor(classColor.r, classColor.g, classColor.b)
                                elseif Win.curDMType == Enum.DamageMeterType.EnemyDamageTaken then
                                    barFrame.fill:SetStatusBarColor(0xDD / 255, 0x31 / 255, 0x31 / 255)
                                else
                                    barFrame.fill:SetStatusBarColor(0.5, 0.5, 0.5)
                                end
                            end
                        elseif fullRebuild or not barFrame._cachedColorClass then
                            barFrame._cachedColorClass = false
                            barFrame._cachedThreatColor = nil
                            if cfg.barColorUseAccent ~= false then
                                local ar2, ag2, ab2 = GetAccentRGB()
                                barFrame.fill:SetStatusBarColor(ar2, ag2, ab2)
                            else
                                local bc = cfg.barColor
                                barFrame.fill:SetStatusBarColor(
                                    bc and bc.r or 0.35,
                                    bc and bc.g or 0.55,
                                    bc and bc.b or 0.8
                                )
                            end
                        end

                        -- Left text color (pos + label)
                        if cfg.leftTextUseClassColor then
                            local classColor = class and RAID_CLASS_COLORS[class] and CUI.GetClassColor(class)
                            local lr, lg, lb = classColor and classColor.r or 1, classColor and classColor.g or 1, classColor and classColor.b or 1
                            barFrame.label:SetTextColor(lr, lg, lb)
                            barFrame.pos:SetTextColor(lr, lg, lb)
                        elseif fullRebuild then
                            local tc = cfg.leftTextColor
                            local lr, lg, lb = tc and tc.r or 1, tc and tc.g or 1, tc and tc.b or 1
                            barFrame.label:SetTextColor(lr, lg, lb)
                            barFrame.pos:SetTextColor(lr, lg, lb)
                        end
                        -- Right text color (amount)
                        if cfg.rightTextUseThreatGradient then
                            mod.DMPaintValueGradient(barFrame, Win, source, i)
                        elseif cfg.rightTextUseClassColor then
                            local classColor = class and RAID_CLASS_COLORS[class] and CUI.GetClassColor(class)
                            local rr, rg, rb = classColor and classColor.r or 1, classColor and classColor.g or 1, classColor and classColor.b or 1
                            barFrame.amount:SetTextColor(rr, rg, rb)
                        elseif fullRebuild then
                            local tc = cfg.rightTextColor
                            local rr, rg, rb = tc and tc.r or 1, tc and tc.g or 1, tc and tc.b or 1
                            barFrame.amount:SetTextColor(rr, rg, rb)
                        end

                        -- Name
                        local srcName = source.name
                        if isSecret and issecretvalue(srcName) then
                            barFrame.label:SetText(StripRealm(srcName, source))
                            barFrame._cachedSrcName = nil
                        elseif srcName ~= barFrame._cachedSrcName then
                            barFrame._cachedSrcName = srcName
                            barFrame._cachedDisplayName = StripRealm(srcName, source)
                            barFrame.label:SetText(barFrame._cachedDisplayName)
                        end

                        -- Amount text (guard secret values -- can't compare)
                        local fmtVal
                        if isThreat then
                            fmtVal = source.threatText
                        elseif isDeaths then
                            local isOverall = (
                                not Win.curSessionID
                                and Win.curSession == Enum.DamageMeterSessionType.Overall
                            )
                            fmtVal = isOverall and ""
                                or mod._DeathTimeText(
                                    source,
                                    not Win.curSessionID
                                        and Win.curSession == Enum.DamageMeterSessionType.Current
                                )
                        elseif isCount then
                            fmtVal = AbbrevNumber(source.totalAmount)
                        else
                            fmtVal = FormatBarValue(source.totalAmount, source.amountPerSecond, numFmt)
                        end
                        if isSecret and issecretvalue(fmtVal) then
                            barFrame.amount:SetText(fmtVal)
                            barFrame._cachedAmtText = nil
                        elseif fmtVal ~= barFrame._cachedAmtText then
                            barFrame._cachedAmtText = fmtVal
                            barFrame.amount:SetText(fmtVal)
                        end
                        barFrame._src = source
                        barFrame._srcGUID = source.sourceGUID
                        barFrame._class = class
                        if rowDecor then mod.DMApplyRowDecor(barFrame, Win, source, i) end
                    end
                else
                    if barFrame.row:IsShown() then barFrame.row:Hide() end
                    barFrame._src = nil
                    barFrame._srcGUID = nil
                    barFrame._class = nil
                    barFrame._cachedSlot = nil
                    barFrame._cachedClass = false
                    barFrame._cachedSpecIcon = nil
                    barFrame._cachedColorClass = false
                    barFrame._cachedSrcName = nil
                    barFrame._cachedDisplayName = nil
                    barFrame._cachedAmtText = nil
                    barFrame._cachedRank = nil
                    barFrame._cachedThreatColor = nil
                end
            end
        else
            for i = 1, BAR_POOL_SIZE do
                Win.rowPool[i].row:Hide()
            end
            Win.cachedSources = nil
            RecalcViewport(0)
            Win.UpdateSticky(nil, 0)
        end
        Win.visibleCount = count
        if Win._decorSync then mod.DMSyncRowDecor(Win) end

        Win.UpdateTimerText()
        local isOverall = (not Win.curSessionID and Win.curSession == Enum.DamageMeterSessionType.Overall)
        local typeName = Loc(DM_TYPE_NAMES[Win.curDMType] or "Damage Done")
        Win._fullTitle = isOverall and CludesUI.Lf("Overall %1$s", typeName) or typeName
        -- A Threat list (WoW Forever) names its mob and has no segments.
        if session and session.threatTitle then Win._fullTitle = session.threatTitle end
        Win.FitTitle()
        if winIdx == 1 then UpdateSATimerText() end

        if Win.sourceOpen then Win.RefreshBreakdown() end
    end

    -- Header combat timer, decoupled from the meter refresh rate: the shared timer ticker calls this
    -- between refreshes so the clock ticks smoothly at slow rates. Memoized on the displayed second (inputs: resolved duration second + the blank state from Overall/no-data gates).
    function Win.UpdateTimerText()
        -- IsVisible covers a hidden timer (hideTimer) and a hidden window alike: no duration
        -- read. The second-memo repaints on the first tick after it shows again, and a
        -- window's OnShow catch-up refresh runs this at once.
        if not Win.timerText or not Win.timerText:IsVisible() then return end
        -- A Threat list (WoW Forever) has no fight clock.
        if Win.curDMType == "threat" then
            if Win._timerSec ~= -1 then
                Win._timerSec = -1
                Win.timerText:SetText("")
            end
            return
        end
        local isOverall = (not Win.curSessionID and Win.curSession == Enum.DamageMeterSessionType.Overall)
        local dur
        if Win.curSessionID then
            -- Historical session: use that session's stored API duration
            if C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions then
                local sess = C_DamageMeter.GetAvailableCombatSessions()
                if sess then
                    for _, s in ipairs(sess) do
                        if s.sessionID == Win.curSessionID then
                            dur = s.durationSeconds
                            break
                        end
                    end
                end
            end
        elseif Win.curSession == Enum.DamageMeterSessionType.Current then
            -- Live "Current" view: derived from the SAME session the bars render, so it resets
            -- on a Current roll and freezes at combat end in lockstep with the bars (see GetCurrentViewDuration)
            dur = GetCurrentViewDuration()
        elseif not isOverall then
            -- Overall never reads a duration (the isOverall gate below blanks its timer)
            dur = C_DamageMeter
                and C_DamageMeter.GetSessionDurationSeconds
                and C_DamageMeter.GetSessionDurationSeconds(Win.curSession)
        end
        -- Hide timer when segment has no data (count == 0) or is Overall
        local sec = -1
        if not isOverall and dur and type(dur) == "number" and dur > 0 and (Win.visibleCount or 0) > 0 then
            sec = math.floor(dur)
        end
        if Win._timerSec == sec then return end
        Win._timerSec = sec
        if sec >= 0 then
            Win.timerText:SetText("(" .. FormatTimer(dur) .. ")")
        else
            Win.timerText:SetText("")
        end
    end

    -- sync: paint in this call even past PEAK_BUDGET (the OnShow catch-up, which must
    -- never leave the pre-hide rows up for a frame).
    function Win.Refresh(sync)
        if not widget then return end
        -- Hidden by any rule (instance rule, the hotkey, a failing global rule, between
        -- hovers, Alt-Z): no fetch, no paint. The frame's OnShow runs one catch-up.
        if not widget:IsVisible() then
            Win._refreshPending = true
            -- The standalone timer rides window 1's refresh and has its own visibility
            if winIdx == 1 then UpdateSATimerText() end
            -- A live Deaths view still stamps its in-combat death times
            mod._DMHiddenDeathsPass(Win)
            return
        end
        -- WoW Forever's Threat type: Forever Essentials' list, no session fetch.
        if Win.curDMType == "threat" then
            RefreshUI(mod.DMThreatSession and mod.DMThreatSession())
            return
        end

        local apiStart = debugprofilestop()
        local session
        if Win.curSessionID and C_DamageMeter and C_DamageMeter.GetCombatSessionFromID then
            local success, s = pcall(C_DamageMeter.GetCombatSessionFromID, Win.curSessionID, Win.curDMType)
            if success then session = s end
        elseif C_DamageMeter and C_DamageMeter.GetCombatSessionFromType then
            session = C_DamageMeter.GetCombatSessionFromType(Win.curSession, Win.curDMType)
        end
        local apiMs = debugprofilestop() - apiStart

        -- If API spiked, defer UI work to next frame so peaks don't stack
        if apiMs > PEAK_BUDGET and not sync then
            C_Timer.After(0, function() RefreshUI(session) end)
        else
            RefreshUI(session)
        end
    end

    function Win.RefreshBreakdown()
        if not Win.sourceOpen then return end
        if not Win.sourceGUID and not Win.sourceCreatureID then return end
        -- Hidden: the OnShow catch-up reaches the breakdown through RefreshUI
        if not widget:IsVisible() then
            Win._refreshPending = true
            return
        end
        if not C_DamageMeter then return end
        EnsureSpellPool()

        local isDeathRecap = (Win.curDMType == Enum.DamageMeterType.Deaths)

        -- Death recap: use C_DeathRecap API instead of combatSpells
        if isDeathRecap then
            local recapID = Win.sourceRecapID
            if recapID and issecretvalue and issecretvalue(recapID) then recapID = nil end
            local events
            if recapID and recapID > 0 and C_DeathRecap and C_DeathRecap.GetRecapEvents then
                local success, raw = pcall(C_DeathRecap.GetRecapEvents, recapID)
                if success and raw and #raw > 0 then events = raw end
            end
            if not events then
                if Win.spellPool then
                    for i = 1, BAR_POOL_SIZE do
                        Win.spellPool[i].row:Hide()
                    end
                end
                return
            end
            -- Same secret discipline as the hover recap: undocumented event
            -- fields may be SECRET mid-combat, so reads are guarded before Lua
            -- touches them or handed whole to engine sinks; plain values render
            -- byte-identically to the pre-combat output.
            local maxHP, maxHPSecret = 1, nil
            if C_DeathRecap.GetRecapMaxHealth then
                local ok2, hp = pcall(C_DeathRecap.GetRecapMaxHealth, recapID)
                if ok2 and hp then
                    if IsSecret(hp) then
                        maxHPSecret = hp
                    elseif type(hp) == "number" and hp > 0 then
                        maxHP = hp
                    end
                end
            end
            -- Events come newest-first from API; reverse to oldest-first
            local reversed = {}
            for ri = #events, 1, -1 do
                reversed[#reversed + 1] = events[ri]
            end
            local cfg = DB()
            local barH, _, stride =
                mod._RowMetrics(cfg.barHeight or 18, cfg.barSpacing or 2, widget:GetEffectiveScale())
            local leftFS = cfg.leftFontSize or cfg.fontSize or 11
            local rightFS = cfg.rightFontSize or cfg.fontSize or 11
            local texPath, texKey = GetBarTexturePath()
            local deathTime = reversed[#reversed] and reversed[#reversed].timestamp
            if IsSecret(deathTime) then deathTime = nil end
            deathTime = deathTime or GetTime()
            local evCount = math.min(#reversed, BAR_POOL_SIZE)
            for i = 1, BAR_POOL_SIZE do
                local barFrame = Win.spellPool[i]
                if i <= evCount then
                    local ev = reversed[i]
                    barFrame.row:Show()
                    barFrame.row:ClearAllPoints()
                    barFrame.row:SetPoint("TOPLEFT", Win.srcContent, "TOPLEFT", 0, -((i - 1) * stride))
                    barFrame.row:SetPoint("TOPRIGHT", Win.srcContent, "TOPRIGHT", 0, -((i - 1) * stride))
                    barFrame.row:SetHeight(barH)
                    -- Spell icon (135274 = melee attack fallback); a secret id
                    -- goes into GetSpellTexture whole (AllowedWhenTainted)
                    local iconOffset = 0
                    local spID = ev.spellId
                    local spIcon
                    if spID and (IsSecret(spID) or spID > 0) then
                        spIcon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spID)
                    end
                    if not spIcon then spIcon = 135274 end
                    local _cz = DB().classIconZoom or 0.06
                    barFrame.classIcon:SetTexture(spIcon)
                    barFrame.classIcon:SetTexCoord(_cz, 1 - _cz, _cz, 1 - _cz)
                    barFrame.classIcon:SetSize(barH, barH)
                    barFrame.classIcon:Show()
                    iconOffset = barH
                    barFrame.fill:ClearAllPoints()
                    barFrame.fill:SetPoint("TOPLEFT", barFrame.row, "TOPLEFT", iconOffset, 0)
                    barFrame.fill:SetPoint("TOPRIGHT", barFrame.row, "TOPRIGHT", 0, 0)
                    barFrame.fill:SetHeight(barH)
                    -- Fill = HP% remaining at this event; secret HP numbers go
                    -- to the StatusBar whole, which divides engine-side
                    local curHP = ev.currentHP or 0
                    local hpPct
                    if not IsSecret(curHP) and not maxHPSecret and type(curHP) == "number" then
                        hpPct = maxHP > 0 and (curHP / maxHP) or 0
                        hpPct = math.min(1, math.max(0, hpPct))
                    end
                    ApplyBarTexture(barFrame.fill, texPath, texKey)
                    if hpPct then
                        barFrame.fill:SetMinMaxValues(0, 1)
                        barFrame.fill:SetValue(hpPct)
                    else
                        barFrame.fill:SetMinMaxValues(0, maxHPSecret or maxHP)
                        barFrame.fill:SetValue(curHP)
                    end
                    local evType = ev.event or ""
                    if IsSecret(evType) then evType = "" end
                    local isHeal = (evType == "SPELL_HEAL" or evType == "SPELL_PERIODIC_HEAL")
                    local isFatal = (i == evCount and not isHeal)
                    if isHeal then
                        barFrame.fill:SetStatusBarColor(0.10, 0.50, 0.10)
                    else
                        barFrame.fill:SetStatusBarColor(0.60, 0.08, 0.08)
                    end
                    SetDMFont(barFrame.label, leftFS)
                    SetDMFont(barFrame.amount, rightFS)
                    barFrame.label:SetTextColor(1, 1, 1)
                    barFrame.amount:SetTextColor(1, 1, 1)
                    -- Label: time before death + spell name. A secret name is
                    -- KEPT (FontStrings display secrets) and engine-formatted
                    -- so it never meets Lua concatenation.
                    local spellName = ev.spellName
                    local nameSecret = IsSecret(spellName)
                    if not nameSecret and (not spellName or spellName == "") then
                        if isHeal then
                            spellName = "Heal"
                        elseif evType == "SWING_DAMAGE" then
                            spellName = "Melee"
                        else
                            spellName = "Unknown"
                        end
                    end
                    local ts = ev.timestamp
                    local td
                    if not IsSecret(ts) then td = deathTime - (ts or deathTime) end
                    if td then
                        barFrame.label:SetFormattedText("-%.1fs %s", td, spellName)
                    else
                        barFrame.label:SetFormattedText("%s", spellName)
                    end
                    -- Amount: damage/heal + overkill on killing blow + HP%
                    local amt = ev.amount or 0
                    local pctStr = hpPct and format(" (%.0f%%)", hpPct * 100) or ""
                    if IsSecret(amt) then
                        -- Secret amount: engine abbreviation, no sign/overkill dressing
                        barFrame.amount:SetFormattedText("%s%s", AbbrevNumber(amt), pctStr)
                    else
                        local amtStr
                        if isHeal then
                            amtStr = "+" .. AbbrevNumber(math.abs(amt))
                        else
                            amtStr = "-" .. AbbrevNumber(amt)
                        end
                        local overkill = ev.overkill
                        if
                            isFatal
                            and overkill
                            and not IsSecret(overkill)
                            and type(overkill) == "number"
                            and overkill > 0
                        then
                            barFrame.amount:SetText(
                                amtStr
                                    .. " |cffff3333("
                                    .. CludesUI.Lf("%1$s overkill", AbbrevNumber(overkill))
                                    .. ")|r"
                                    .. pctStr
                            )
                        else
                            barFrame.amount:SetText(amtStr .. pctStr)
                        end
                    end
                    barFrame._spellID = spID
                else
                    barFrame.row:Hide()
                    barFrame._spellID = nil
                end
            end
            local srcTotalH = evCount * stride
            Win.srcContent:SetHeight(math.max(10, srcTotalH))
            local srcViewH = Win.srcViewport:GetHeight()
            if srcViewH < 1 then srcViewH = 1 end
            _srcScrollMax = math.max(0, srcTotalH - srcViewH)
            return
        end

        -- Enemy Damage Taken: show per-player breakdown instead of per-spell
        if Win.curDMType == Enum.DamageMeterType.EnemyDamageTaken then
            local unitGuid = Win.sourceGUID
            local cid = Win.sourceCreatureID
            local srcData
            if Win.curSessionID and C_DamageMeter.GetCombatSessionSourceFromID then
                local success, sd = pcall(
                    C_DamageMeter.GetCombatSessionSourceFromID,
                    Win.curSessionID,
                    Win.curDMType,
                    unitGuid,
                    cid
                )
                if success then srcData = sd end
            elseif C_DamageMeter.GetCombatSessionSourceFromType then
                local success, sd = pcall(
                    C_DamageMeter.GetCombatSessionSourceFromType,
                    Win.curSession,
                    Win.curDMType,
                    unitGuid,
                    cid
                )
                if success then srcData = sd end
            end
            local cfg = DB()
            local barH, _, stride =
                mod._RowMetrics(cfg.barHeight or 18, cfg.barSpacing or 2, widget:GetEffectiveScale())
            -- Rows and the icon lookup's source are kept on the window: this
            -- runs on every meter refresh while the breakdown is open.
            Win._enemyRows = Win._enemyRows or {}
            local players, playerCount = AggregateEnemyPlayers(
                srcData,
                GetBreakdownDuration(Win.curSession, Win.curSessionID),
                Win._enemyRows
            )
            if not players then
                if Win.spellPool then
                    for i = 1, BAR_POOL_SIZE do
                        Win.spellPool[i].row:Hide()
                    end
                end
                return
            end
            local leftFS = cfg.leftFontSize or cfg.fontSize or 11
            local rightFS = cfg.rightFontSize or cfg.fontSize or 11
            local texPath, texKey = GetBarTexturePath()
            local maxAmt = players[1].total
            local pCount = math.min(playerCount, BAR_POOL_SIZE)
            local iconSrc = Win._enemyIconSrc or {}
            Win._enemyIconSrc = iconSrc
            for i = 1, BAR_POOL_SIZE do
                local barFrame = Win.spellPool[i]
                if i <= pCount then
                    local p = players[i]
                    barFrame.row:Show()
                    barFrame.row:ClearAllPoints()
                    barFrame.row:SetPoint("TOPLEFT", Win.srcContent, "TOPLEFT", 0, -((i - 1) * stride))
                    barFrame.row:SetPoint("TOPRIGHT", Win.srcContent, "TOPRIGHT", 0, -((i - 1) * stride))
                    barFrame.row:SetHeight(barH)
                    -- Class/spec icon via ResolveIcon (consistent with main bars)
                    iconSrc.classFilename, iconSrc.specIconID = p.class, p.specIcon
                    local iconOffset = ResolveIcon(iconSrc, barFrame.classIcon, barH)
                    barFrame.fill:ClearAllPoints()
                    barFrame.fill:SetPoint("TOPLEFT", barFrame.row, "TOPLEFT", iconOffset, 0)
                    barFrame.fill:SetPoint("TOPRIGHT", barFrame.row, "TOPRIGHT", 0, 0)
                    barFrame.fill:SetHeight(barH)
                    ApplyBarTexture(barFrame.fill, texPath, texKey)
                    barFrame.fill:SetMinMaxValues(0, maxAmt)
                    barFrame.fill:SetValue(p.total)
                    local classColor = p.class and RAID_CLASS_COLORS[p.class] and CUI.GetClassColor(p.class)
                    if classColor then
                        barFrame.fill:SetStatusBarColor(classColor.r, classColor.g, classColor.b)
                    else
                        local ar2, ag2, ab2 = GetAccentRGB()
                        barFrame.fill:SetStatusBarColor(ar2, ag2, ab2)
                    end
                    SetDMFont(barFrame.label, leftFS)
                    SetDMFont(barFrame.amount, rightFS)
                    barFrame.label:SetTextColor(1, 1, 1)
                    barFrame.amount:SetTextColor(1, 1, 1)
                    barFrame.label:SetText(StripRealm(p.name, nil, p))
                    barFrame.amount:SetText(FormatBarValue(p.total, p.amountPerSecond, cfg.numberFormat or 2))
                    barFrame._spellID = nil
                else
                    barFrame.row:Hide()
                    barFrame._spellID = nil
                end
            end
            local srcTotalH = pCount * stride
            Win.srcContent:SetHeight(math.max(10, srcTotalH))
            local srcViewH = Win.srcViewport:GetHeight()
            if srcViewH < 1 then srcViewH = 1 end
            _srcScrollMax = math.max(0, srcTotalH - srcViewH)
            return
        end

        -- Standard spell breakdown (non-Deaths)
        -- Pass guid/cid straight through -- API accepts its own secret values
        local unitGuid = Win.sourceGUID
        local cid = Win.sourceCreatureID
        local srcData
        if Win.curSessionID and C_DamageMeter.GetCombatSessionSourceFromID then
            local success, sd = pcall(
                C_DamageMeter.GetCombatSessionSourceFromID,
                Win.curSessionID,
                Win.curDMType,
                unitGuid,
                cid
            )
            if success then srcData = sd end
        elseif C_DamageMeter.GetCombatSessionSourceFromType then
            local success, sd = pcall(
                C_DamageMeter.GetCombatSessionSourceFromType,
                Win.curSession,
                Win.curDMType,
                unitGuid,
                cid
            )
            if success then srcData = sd end
        end
        if not srcData or not srcData.combatSpells then
            if Win.spellPool then
                for i = 1, BAR_POOL_SIZE do
                    Win.spellPool[i].row:Hide()
                end
            end
            return
        end
        local spells = srcData.combatSpells
        local cfg = DB()
        local barH, barSp, stride =
            mod._RowMetrics(cfg.barHeight or 18, cfg.barSpacing or 2, widget:GetEffectiveScale())
        local leftFS = cfg.leftFontSize or cfg.fontSize or 11
        local rightFS = cfg.rightFontSize or cfg.fontSize or 11
        local texPath, texKey = GetBarTexturePath()
        local sorted = {}
        for _, spell in ipairs(spells) do
            local success, amt = pcall(function() return spell.totalAmount end)
            sorted[#sorted + 1] = { spell = spell, amount = (success and amt) or 0 }
        end
        -- API returns combatSpells pre-sorted; no table.sort needed
        local maxAmt = sorted[1] and sorted[1].amount or 1
        -- Sum totals for percentage (skip if amounts are secret)
        local totalDmg = 0
        local canPercent = maxAmt
            and (not issecretvalue or not issecretvalue(maxAmt))
            and type(maxAmt) == "number"
        if canPercent then
            for _, entry in ipairs(sorted) do
                totalDmg = totalDmg + entry.amount
            end
        end
        local spCount = math.min(#sorted, BAR_POOL_SIZE)
        for i = 1, BAR_POOL_SIZE do
            local barFrame = Win.spellPool[i]
            if i <= spCount then
                local record = sorted[i]
                local spell = record.spell
                barFrame.row:Show()
                barFrame.row:ClearAllPoints()
                local yOff2 = -((i - 1) * stride)
                barFrame.row:SetPoint("TOPLEFT", Win.srcContent, "TOPLEFT", 0, yOff2)
                barFrame.row:SetPoint("TOPRIGHT", Win.srcContent, "TOPRIGHT", 0, yOff2)
                barFrame.row:SetHeight(barH)
                local iconOffset = 0
                -- Same secret-spellID handling as the tooltip breakdown (PopulatePreview): a
                -- secret id goes through pcall and its result is tested by type().
                local spID = spell.spellID
                local getTex = C_Spell and C_Spell.GetSpellTexture
                local spIcon, haveIcon
                if spID and getTex then
                    if IsSecret(spID) then
                        local success, texture = pcall(getTex, spID)
                        if success and type(texture) ~= "nil" then
                            spIcon, haveIcon = texture, true
                        end
                    else
                        spIcon = getTex(spID)
                        haveIcon = spIcon and true or false
                    end
                end
                if haveIcon then
                    local _cz = DB().classIconZoom or 0.06
                    barFrame.classIcon:SetTexture(spIcon)
                    barFrame.classIcon:SetTexCoord(_cz, 1 - _cz, _cz, 1 - _cz)
                    barFrame.classIcon:SetSize(barH, barH)
                    barFrame.classIcon:Show()
                    iconOffset = barH
                else
                    barFrame.classIcon:Hide()
                end
                barFrame.fill:ClearAllPoints()
                barFrame.fill:SetPoint("TOPLEFT", barFrame.row, "TOPLEFT", iconOffset, 0)
                barFrame.fill:SetPoint("TOPRIGHT", barFrame.row, "TOPRIGHT", 0, 0)
                barFrame.fill:SetHeight(barH)
                ApplyBarTexture(barFrame.fill, texPath, texKey)
                barFrame.fill:SetMinMaxValues(0, maxAmt)
                barFrame.fill:SetValue(record.amount)
                if Win.sourceClass and RAID_CLASS_COLORS[Win.sourceClass] then
                    local cc = CUI.GetClassColor(Win.sourceClass)
                    barFrame.fill:SetStatusBarColor(cc.r, cc.g, cc.b)
                else
                    local ar2, ag2, ab2 = GetAccentRGB()
                    barFrame.fill:SetStatusBarColor(ar2, ag2, ab2)
                end
                SetDMFont(barFrame.label, leftFS)
                SetDMFont(barFrame.amount, rightFS)
                local spellName
                if spell.spellID then
                    local okS, sn = pcall(
                        function()
                            return C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spell.spellID)
                        end
                    )
                    spellName = (okS and sn) or nil
                end
                barFrame.label:SetText(spellName or spell.creatureName or Loc("Unknown"))
                if canPercent and totalDmg > 0 then
                    barFrame.amount:SetText(
                        format("%s  %.1f%%", AbbrevNumber(record.amount), (record.amount / totalDmg) * 100)
                    )
                else
                    barFrame.amount:SetText(AbbrevNumber(record.amount))
                end
                barFrame._spellID = spell.spellID
            else
                barFrame.row:Hide()
                barFrame._spellID = nil
            end
        end

        -- Targets section (DamageDone only): show top 3 enemies this player hit.
        -- Skipped in combat: it cross-references and COMPARES amounts across
        -- sources in Lua, which secrets cannot survive.
        local targetsRendered = 0
        if Win.curDMType == Enum.DamageMeterType.DamageDone and not InCombatLockdown() then
            if not Win._cachedTargets then
                Win._cachedTargets = BuildPlayerTargets(
                    Win.sourceRawName,
                    Win.curSession,
                    Win.curSessionID,
                    3
                ) or false
            end
            local tList = Win._cachedTargets
            if tList and tList ~= false then
                -- Divider + "Targets" label
                local divY = -(spCount * stride + barSp * 2)
                if not Win._targetDivider then
                    Win._targetDivider = Win.srcContent:CreateTexture(nil, "ARTWORK")
                    Win._targetDivider:SetHeight(PhysicalPixels(1))
                    Win._targetDivider:SetColorTexture(1, 1, 1, 0.15)
                    Win._targetLabel = Win.srcContent:CreateFontString(nil, "OVERLAY")
                    SetDMFont(Win._targetLabel, leftFS - 1)
                    Win._targetLabel:SetTextColor(0.6, 0.6, 0.6, 1)
                    Win._targetLabel:SetText(CludesUI.L("Targets"))
                end
                Win._targetDivider:ClearAllPoints()
                Win._targetDivider:SetPoint("TOPLEFT", Win.srcContent, "TOPLEFT", 0, divY)
                Win._targetDivider:SetPoint("TOPRIGHT", Win.srcContent, "TOPRIGHT", 0, divY)
                Win._targetDivider:Show()
                local labelY = divY - barSp - 10
                Win._targetLabel:ClearAllPoints()
                Win._targetLabel:SetPoint("LEFT", Win.srcContent, "TOPLEFT", 3, labelY)
                SetDMFont(Win._targetLabel, leftFS - 1)
                Win._targetLabel:Show()

                local tStartY = labelY - 12
                local tMaxAmt = tList[1].total
                for ti = 1, #tList do
                    local tIdx = spCount + ti
                    if tIdx > BAR_POOL_SIZE then break end
                    local barFrame = Win.spellPool[tIdx]
                    local tbl = tList[ti]
                    barFrame.row:Show()
                    barFrame.row:ClearAllPoints()
                    barFrame.row:SetPoint(
                        "TOPLEFT",
                        Win.srcContent,
                        "TOPLEFT",
                        0,
                        tStartY - ((ti - 1) * stride)
                    )
                    barFrame.row:SetPoint(
                        "TOPRIGHT",
                        Win.srcContent,
                        "TOPRIGHT",
                        0,
                        tStartY - ((ti - 1) * stride)
                    )
                    barFrame.row:SetHeight(barH)
                    barFrame.classIcon:Hide()
                    barFrame.fill:ClearAllPoints()
                    barFrame.fill:SetPoint("TOPLEFT", barFrame.row, "TOPLEFT", 0, 0)
                    barFrame.fill:SetPoint("TOPRIGHT", barFrame.row, "TOPRIGHT", 0, 0)
                    barFrame.fill:SetHeight(barH)
                    ApplyBarTexture(barFrame.fill, texPath, texKey)
                    barFrame.fill:SetMinMaxValues(0, tMaxAmt)
                    barFrame.fill:SetValue(tbl.total)
                    barFrame.fill:SetStatusBarColor(0xDD / 255, 0x31 / 255, 0x31 / 255)
                    SetDMFont(barFrame.label, leftFS)
                    SetDMFont(barFrame.amount, rightFS)
                    barFrame.label:SetTextColor(1, 1, 1)
                    barFrame.amount:SetTextColor(1, 1, 1)
                    barFrame.label:SetText(tbl.name)
                    barFrame.amount:SetText(
                        FormatBarValue(tbl.total, tbl.amountPerSecond, cfg.numberFormat or 2)
                    )
                    barFrame._spellID = nil
                    targetsRendered = targetsRendered + 1
                end
            end
        end
        -- Hide divider/label if no targets
        if targetsRendered == 0 then
            if Win._targetDivider then Win._targetDivider:Hide() end
            if Win._targetLabel then Win._targetLabel:Hide() end
        end

        local extraH = 0
        if targetsRendered > 0 then
            -- divider gap + label + target bars
            extraH = (barSp * 2) + 1 + barSp + 10 + 12 + (targetsRendered * stride)
        end
        local srcTotalH = spCount * stride + extraH
        Win.srcContent:SetHeight(math.max(10, srcTotalH))
        local srcViewH = Win.srcViewport:GetHeight()
        if srcViewH < 1 then srcViewH = 1 end
        _srcScrollMax = math.max(0, srcTotalH - srcViewH)
    end

    function Win.OpenSource(unitGuid, creatureID, name, class, recapID, rawName)
        if not Win.sourceFrame then return end
        Win.sourceGUID = unitGuid
        Win.sourceCreatureID = creatureID
        Win.sourceClass = class
        Win.sourceOpen = true
        Win.sourceRecapID = recapID
        Win.sourceRawName = rawName
        Win._cachedTargets = nil
        Win.HideHome()
        if viewport then viewport:Hide() end
        if Win.stickyPlayer then Win.stickyPlayer.row:Hide() end
        if Win.stickySep then Win.stickySep:Hide() end
        if Win._decorSync then mod.DMSyncRowDecor(Win) end
        if widget._bg then widget._bg:Hide() end
        Win.sourceFrame:Show()
        Win.RefreshBreakdown()
    end

    function Win.CloseSource()
        local wasOpen = Win.sourceOpen
        Win.sourceOpen = false
        Win.sourceGUID = nil
        Win.sourceCreatureID = nil
        Win.sourceRecapID = nil
        Win.sourceRawName = nil
        Win._cachedTargets = nil
        if Win.sourceFrame then Win.sourceFrame:Hide() end
        if viewport then viewport:Show() end
        if widget._bg then widget._bg:Show() end
        Win.UpdateSticky(nil, Win.visibleCount)
        if Win._decorSync then mod.DMSyncRowDecor(Win) end
        -- The last pass skipped the pin state while the source was up: rows it reveals need a fill.
        if wasOpen then Win.QueueRepopulate() end
    end

    -- Home screen (quick links grid): 2-column card layout with accent indicators, + add button, hint text
    local homeScroll, homeChild -- homeFrame is forward-declared above
    local homeCards = {}
    local homeAddBtn, homeTitle
    local _homeScrollMax = 0
    local CARD_H = 26
    local CARD_GAP = 4
    local CARD_COL_GAP = 4
    local CARD_PAD_X = 8
    local CARD_PAD_TOP = 6
    local CARD_BG_R, CARD_BG_G, CARD_BG_B, CARD_BG_A = 0.12, 0.12, 0.12, 0.8
    local CARD_HL_A = 0.18

    local function MakeCard(hostFrame)
        local cardFrame = CreateFrame("Button", nil, hostFrame)
        cardFrame:SetHeight(CARD_H)
        cardFrame:RegisterForClicks("AnyUp")

        cardFrame._bg = cardFrame:CreateTexture(nil, "BACKGROUND")
        cardFrame._bg:SetAllPoints()
        cardFrame._bg:SetColorTexture(CARD_BG_R, CARD_BG_G, CARD_BG_B, CARD_BG_A)

        cardFrame._accent = cardFrame:CreateTexture(nil, "ARTWORK")
        cardFrame._accent:SetWidth(2)
        cardFrame._accent:SetPoint("TOPLEFT", cardFrame, "TOPLEFT", 0, 0)
        cardFrame._accent:SetPoint("BOTTOMLEFT", cardFrame, "BOTTOMLEFT", 0, 0)
        cardFrame._accent:Hide()

        local fontFile = (CUI.GetFontPath("damageMeters")) or "Fonts\\FRIZQT__.TTF"
        local outline = (CUI.GetFontOutlineFlag("damageMeters")) or ""
        local iconSz = CARD_H - 2
        cardFrame._icon = cardFrame:CreateTexture(nil, "OVERLAY")
        cardFrame._icon:SetSize(iconSz, iconSz)
        cardFrame._icon:SetPoint("LEFT", cardFrame, "LEFT", 6, 0)
        cardFrame._icon:SetDesaturated(true)

        cardFrame._lbl = cardFrame:CreateFontString(nil, "OVERLAY")
        cardFrame._lbl:SetFont(fontFile, CTX_FONT_SZ, outline)
        cardFrame._lbl:SetPoint("LEFT", cardFrame._icon, "RIGHT", 5, 0)
        cardFrame._lbl:SetPoint("RIGHT", cardFrame, "RIGHT", -30, 0)
        cardFrame._lbl:SetJustifyH("LEFT")
        cardFrame._lbl:SetWordWrap(false)

        cardFrame._arrow = cardFrame:CreateTexture(nil, "ARTWORK")
        cardFrame._arrow:SetTexture(CTX_ARROW_ICON)
        cardFrame._arrow:SetSize(18, 18)
        cardFrame._arrow:SetPoint("RIGHT", cardFrame, "RIGHT", -4, 0)
        cardFrame._arrow:SetRotation(math.pi / 2)
        cardFrame._arrow:SetVertexColor(1, 1, 1, 1)

        return cardFrame
    end

    RefreshHome = function()
        if not homeFrame or not homeFrame:IsShown() then return end
        local bookmarks = GetBookmarks()
        local fontFile = (CUI.GetFontPath("damageMeters")) or "Fonts\\FRIZQT__.TTF"
        local outline = (CUI.GetFontOutlineFlag("damageMeters")) or ""
        local ACC = CUI.CLUDES_GREEN
        local acR, acG, acB = GetAccentRGB()
        -- WoW Forever: the header's tan glyphs in place of the accent.
        local fvG = mod.DMForever() and mod.DM_FV.glyph

        -- Calculate column width from scroll frame. An unplaced window (an
        -- unlock-anchored one before the login anchor pass lands) has no
        -- width yet; laying out from zero would collapse every card. The
        -- scroll frame's size hook runs this again once the width arrives.
        local totalW = homeScroll and homeScroll:GetWidth() or homeFrame:GetWidth()
        if not totalW or totalW < 1 then return end
        local colW = (totalW - CARD_PAD_X * 2 - CARD_COL_GAP) / 2

        -- Hide all existing cards
        for _, c in ipairs(homeCards) do
            c:Hide()
        end

        -- Layout bookmarks in 2-column grid. Cards go by display position (shown);
        -- idx stays the bookmark's place in the saved list, for removal.
        local row, colour = 0, 0
        local startY = -CARD_PAD_TOP
        local isShown = 0

        for index, dmType in mod.DMHomeTypes(bookmarks) do
            isShown = isShown + 1
            local cardFrame = homeCards[isShown]
            if not cardFrame then
                cardFrame = MakeCard(homeChild)
                homeCards[isShown] = cardFrame
            end

            local labelText = Loc(DM_TYPE_NAMES[dmType] or "Unknown")
            local isActive = (dmType == Win.curDMType)

            local xOff = CARD_PAD_X + colour * (colW + CARD_COL_GAP)
            local yOff = startY - row * (CARD_H + CARD_GAP)
            cardFrame:ClearAllPoints()
            cardFrame:SetPoint("TOPLEFT", homeChild, "TOPLEFT", xOff, yOff)
            cardFrame:SetWidth(colW)

            -- WoW Forever: Forever's list buttons, the selected one marking
            -- the active meter (no accent strip).
            if not mod.DMFvCard(cardFrame._bg, isActive and "selected" or "normal") then
                cardFrame._bg:SetColorTexture(CARD_BG_R, CARD_BG_G, CARD_BG_B, CARD_BG_A)
            end
            cardFrame._lbl:SetFont(fontFile, CTX_FONT_SZ, outline)
            cardFrame._lbl:SetText(labelText)
            cardFrame._icon:SetTexture(DM_TYPE_ICONS[dmType] or MEDIA .. "dm_home_damage.png")
            cardFrame._arrow:Show()

            if isActive then
                cardFrame._accent:SetColorTexture(acR, acG, acB, 1)
                cardFrame._accent:SetShown(not mod._dmForever)
                if fvG then
                    cardFrame._icon:SetVertexColor(fvG[1], fvG[2], fvG[3], 1)
                else
                    cardFrame._icon:SetVertexColor(acR, acG, acB, 1)
                end
                cardFrame._lbl:SetTextColor(1, 1, 1, 1)
                cardFrame._arrow:SetVertexColor(1, 1, 1, 1)
            else
                cardFrame._accent:Hide()
                if fvG then
                    local scale = mod.DM_HDR_IDLE
                    cardFrame._icon:SetVertexColor(fvG[1] * scale, fvG[2] * scale, fvG[3] * scale, 1)
                else
                    cardFrame._icon:SetVertexColor(acR, acG, acB, 0.6)
                end
                cardFrame._lbl:SetTextColor(1, 1, 1, 0.8)
                cardFrame._arrow:SetVertexColor(1, 1, 1, 1)
            end

            cardFrame:SetScript("OnEnter", function(self)
                if not mod.DMFvCard(self._bg, "hover") then
                    self._bg:SetColorTexture(
                        CARD_BG_R + 0.06,
                        CARD_BG_G + 0.06,
                        CARD_BG_B + 0.06,
                        CARD_BG_A + CARD_HL_A
                    )
                end
                self._lbl:SetTextColor(1, 1, 1, 1)
                self._arrow:SetVertexColor(1, 1, 1, 1)
            end)
            cardFrame:SetScript("OnLeave", function(self)
                if not mod.DMFvCard(self._bg, isActive and "selected" or "normal") then
                    self._bg:SetColorTexture(CARD_BG_R, CARD_BG_G, CARD_BG_B, CARD_BG_A)
                end
                if isActive then
                    self._lbl:SetTextColor(1, 1, 1, 1)
                    self._arrow:SetVertexColor(1, 1, 1, 1)
                else
                    self._lbl:SetTextColor(1, 1, 1, 0.8)
                    self._arrow:SetVertexColor(1, 1, 1, 1)
                end
            end)
            cardFrame:SetScript("OnClick", function(_, btnFrame)
                if btnFrame == "MiddleButton" then
                    table.remove(bookmarks, index)
                    RefreshHome()
                elseif btnFrame == "LeftButton" then
                    Win.HideHome()
                    Win.SetDMType(dmType)
                end
            end)

            cardFrame:Show()
            colour = colour + 1
            if colour >= 2 then
                colour = 0
                row = row + 1
            end
        end

        -- "+ ADD NEW" button (full width, below the grid), while a type this client
        -- offers has no card yet
        local addRow = (colour > 0) and (row + 1) or row
        local offered = 0
        for _ in pairs(DM_TYPE_NAMES) do
            offered = offered + 1
        end
        if isShown < offered then
            if not homeAddBtn then
                homeAddBtn = CreateFrame("Button", nil, homeChild)
                homeAddBtn:SetHeight(CARD_H)
                homeAddBtn._bg = homeAddBtn:CreateTexture(nil, "BACKGROUND")
                homeAddBtn._bg:SetAllPoints()
                homeAddBtn._plus = homeAddBtn:CreateFontString(nil, "OVERLAY")
                homeAddBtn._lbl = homeAddBtn:CreateFontString(nil, "OVERLAY")
                homeAddBtn._hint = homeAddBtn:CreateFontString(nil, "OVERLAY")
                homeAddBtn._plus:SetPoint("RIGHT", homeAddBtn._lbl, "LEFT", -4, 0)
                homeAddBtn._hint:SetPoint("LEFT", homeAddBtn._lbl, "RIGHT", 6, 0)
            end
            if not mod.DMFvCard(homeAddBtn._bg, "normal", 0.5) then
                homeAddBtn._bg:SetColorTexture(CARD_BG_R, CARD_BG_G, CARD_BG_B, CARD_BG_A * 0.5)
            end
            homeAddBtn._plus:SetFont(fontFile, 13, outline)
            homeAddBtn._plus:SetText("+")
            homeAddBtn._plus:SetTextColor(1, 1, 1, 0.3)
            homeAddBtn._lbl:SetFont(fontFile, CTX_FONT_SZ, outline)
            homeAddBtn._lbl:SetText(CludesUI.L("ADD NEW"))
            homeAddBtn._lbl:SetTextColor(1, 1, 1, 0.3)
            homeAddBtn._hint:SetFont(fontFile, 9, outline)
            homeAddBtn._hint:SetText(CludesUI.L("(middle click to remove)"))
            homeAddBtn._hint:SetTextColor(1, 1, 1, 0.3)
            -- Center the group: offset label so plus+label+hint are visually centered
            local plusW = homeAddBtn._plus:GetStringWidth() + 4
            local hintW = 6 + homeAddBtn._hint:GetStringWidth()
            local shift = (plusW - hintW) / 2
            homeAddBtn._lbl:ClearAllPoints()
            homeAddBtn._lbl:SetPoint("CENTER", homeAddBtn, "CENTER", shift, 0)
            homeAddBtn:ClearAllPoints()
            homeAddBtn:SetPoint(
                "TOPLEFT",
                homeChild,
                "TOPLEFT",
                CARD_PAD_X,
                startY - addRow * (CARD_H + CARD_GAP)
            )
            homeAddBtn:SetPoint(
                "TOPRIGHT",
                homeChild,
                "TOPRIGHT",
                -CARD_PAD_X,
                startY - addRow * (CARD_H + CARD_GAP)
            )
            homeAddBtn:SetScript("OnEnter", function(self)
                if not mod.DMFvCard(self._bg, "hover", 0.7) then
                    self._bg:SetColorTexture(
                        CARD_BG_R + 0.04,
                        CARD_BG_G + 0.04,
                        CARD_BG_B + 0.04,
                        CARD_BG_A * 0.7
                    )
                end
                self._lbl:SetTextColor(1, 1, 1, 0.5)
                self._plus:SetTextColor(1, 1, 1, 0.5)
            end)
            homeAddBtn:SetScript("OnLeave", function(self)
                if not mod.DMFvCard(self._bg, "normal", 0.5) then
                    self._bg:SetColorTexture(CARD_BG_R, CARD_BG_G, CARD_BG_B, CARD_BG_A * 0.5)
                end
                self._lbl:SetTextColor(1, 1, 1, 0.3)
                self._plus:SetTextColor(1, 1, 1, 0.3)
            end)
            homeAddBtn:SetScript("OnClick", function()
                local itemList = {}
                for dt, num in pairs(DM_TYPE_NAMES) do
                    local pinned = false
                    for _, b in ipairs(bookmarks) do
                        if b == dt then
                            pinned = true
                            break
                        end
                    end
                    if not pinned then
                        itemList[#itemList + 1] = {
                            text = CludesUI.L(num),
                            onClick = function()
                                bookmarks[#bookmarks + 1] = dt
                                RefreshHome()
                            end,
                        }
                    end
                end
                table.sort(itemList, function(a2, b2) return a2.text < b2.text end)
                ShowEDMMenu(itemList)
            end)
            homeAddBtn:Show()
            addRow = addRow + 1
        elseif homeAddBtn then
            homeAddBtn:Hide()
        end

        -- Set scroll child height to fit all content + 5px bottom padding
        local contentH = math.abs(startY) + addRow * (CARD_H + CARD_GAP) + 5
        homeChild:SetHeight(math.max(10, contentH))

        if homeScroll then
            local viewH = homeScroll:GetHeight()
            _homeScrollMax = math.max(0, contentH - viewH)
            local current = homeScroll:GetVerticalScroll() or 0
            if current > _homeScrollMax then homeScroll:SetVerticalScroll(_homeScrollMax) end
        end
    end

    function Win.ShowHome()
        if not homeFrame then
            homeFrame = CreateFrame("Frame", nil, widget)
            homeFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
            homeFrame:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
            homeFrame:SetFrameLevel(widget:GetFrameLevel() + 25)
            homeFrame:EnableMouse(true)
            homeFrame:Hide()

            local hBg = homeFrame:CreateTexture(nil, "BACKGROUND")
            hBg:SetAllPoints()
            hBg:SetColorTexture(0.03, 0.03, 0.03, 0.95)

            homeScroll = CreateFrame("ScrollFrame", nil, homeFrame)
            homeScroll:SetPoint("TOPLEFT", homeFrame, "TOPLEFT", 0, 0)
            homeScroll:SetPoint("BOTTOMRIGHT", homeFrame, "BOTTOMRIGHT", 0, 0)
            homeChild = CreateFrame("Frame", nil, homeScroll)
            homeChild:SetSize(1, 1)
            homeScroll:SetScrollChild(homeChild)
            homeScroll:SetScript("OnSizeChanged", function(_, wid)
                homeChild:SetWidth(wid)
                -- The grid is laid out from this width: re-flow it when the
                -- width changes while the page is up (first placement of an
                -- anchored window, a resize).
                if wid and wid > 1 and homeFrame:IsShown() then RefreshHome() end
            end)

            -- Mouse wheel scrolling (no visual scrollbar)
            local function HomeWheel(_, delta)
                local current = homeScroll:GetVerticalScroll() or 0
                homeScroll:SetVerticalScroll(math.max(0, math.min(_homeScrollMax, current - delta * 30)))
            end
            homeScroll:EnableMouseWheel(true)
            homeScroll:SetScript("OnMouseWheel", HomeWheel)
            homeFrame:EnableMouseWheel(true)
            homeFrame:SetScript("OnMouseWheel", HomeWheel)

            homeFrame:SetScript("OnMouseDown", function(_, btnFrame)
                if btnFrame == "RightButton" then Win.HideHome() end
            end)
        end

        if viewport then viewport:Hide() end
        if Win.stickyPlayer then Win.stickyPlayer.row:Hide() end
        if Win.stickySep then Win.stickySep:Hide() end
        if widget._bg then widget._bg:Hide() end
        homeFrame:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -ci, ci)
        homeFrame:Show()
        if Win._decorSync then mod.DMSyncRowDecor(Win) end
        RefreshHome()
    end

    function Win.HideHome()
        local wasUp = homeFrame and homeFrame:IsShown()
        if homeFrame then homeFrame:Hide() end
        if viewport then viewport:Show() end
        if Win._decorSync then mod.DMSyncRowDecor(Win) end
        if widget._bg then widget._bg:Show() end
        -- ShowHome hid the pinned row on its pinned anchors: re-run the pin pass (OpenSource sets sourceOpen first).
        if wasUp and not Win.sourceOpen then Win.QueueRepopulate() end
    end

    function Win.ToggleHome()
        if homeFrame and homeFrame:IsShown() then
            Win.HideHome()
        else
            Win.ShowHome()
        end
    end

    -- (Refresh ticker is shared across all windows -- see CUI_DamageMeters_Lifecycle.lua)

    -- Per-window instance rules (Hide in Dungeons / Raids / Delves / PvP / out of
    -- Instances); shared by UpdateVisibility and the mouseover predicate below.
    local function InstanceHidden()
        local _, iType = IsInInstance()
        if wdb.hideInDungeon and iType == "party" then return true end
        if wdb.hideInRaid and iType == "raid" then return true end
        if wdb.hideInDelve and CUI.IsInDelve() then return true end
        if wdb.hideInPvP and (iType == "pvp" or iType == "arena") then return true end
        if wdb.hideOutOfInstance and (iType == "none" or iType == nil) then return true end
        return false
    end

    -- Visibility
    function Win.UpdateVisibility()
        if not widget then return end
        local cfg = DB()
        if CUI._unlockActive or mod._optionsOpen then
            widget:SetAlpha(1)
            widget:EnableMouse(true)
            widget:Show()
            return
        end
        -- Hotkey toggle outranks every configured rule but yields to the two modes above
        if mod._toggleHidden then
            widget:Hide()
            return
        end
        local vis = CUI.EvalVisibility(cfg)
        if not vis or vis == false then
            widget:Hide()
            return
        end
        -- Per-window instance visibility
        if InstanceHidden() then
            widget:Hide()
            return
        end
        if vis == "mouseover" then
            widget:Hide()
        else
            widget:SetAlpha(1)
            widget:EnableMouse(true)
            widget:Show()
        end
    end

    -- The mouseover scan's predicate (registered here and again by W.Reapply). Hover-gated
    -- sets only reveal while their conditions pass; a legacy single "mouseover" behaves exactly as before
    local function MouseoverActive()
        -- The mouseover scanner shows the frame without going through UpdateVisibility,
        -- so the toggle and the window's instance rules have to be refused here as well
        if mod._toggleHidden or InstanceHidden() then return false end
        local cfg = DB()
        return cfg ~= nil and CUI.VisWantsMouseover(cfg, "visibility")
    end
    CUI.RegisterVisibilityUpdater(Win.UpdateVisibility)
    if CUI.RegisterMouseoverTarget then CUI.RegisterMouseoverTarget(widget, MouseoverActive) end

    -- Catch-up: refreshes skipped while hidden leave W._refreshPending, so the first show
    -- (a rule, the hotkey, a hover, the options preview, Alt-Z) repaints once, in-call,
    -- before the frame draws; then the ticks a fully hidden meter let lapse come back.
    widget:HookScript("OnShow", function()
        -- A Threat window (WoW Forever) always repaints: its list stops while
        -- no Threat window is on screen.
        if Win._refreshPending or Win.curDMType == "threat" then
            Win._refreshPending = nil
            Win.Refresh(true)
        end
        mod._DMReviveTicks()
    end)
    -- (Only where the Threat type is offered: set at login, before any window is built.)
    if DM_TYPE_NAMES.threat then
        widget:HookScript("OnHide", function()
            if Win.curDMType == "threat" then mod.DMThreatSync(Win) end
        end)
    end

    -- Park: takes this window out of use and keeps it whole for W.Reapply (a closed
    -- window, or one past a profile's window count): hidden, out of the visibility
    -- updates and the mouseover scan (no ghost resurrection), any hover, drag or
    -- resize ended, and listed in ns._dmParked.
    function Win.Park()
        if Win._parked then return end
        Win._parked = true
        dragging = false
        dragFrame:Hide()
        Win.resizing = false
        resizeFrame:Hide()
        Win._endHover()
        widget:Hide()
        CUI.UnregisterVisibilityUpdater(Win.UpdateVisibility)
        CUI.UnregisterMouseoverTarget(widget)
        local parked = mod._dmParked
        parked[#parked + 1] = Win
    end

    -- Destroy (the close button): the window is parked and its slot removed (a window
    -- already parked holds no slot)
    function Win.Destroy()
        if Win._parked then return end
        Win.Park()
        -- Remove from runtime array
        local oldCount = #_windows
        local runtimeIdx
        for i, wid in ipairs(_windows) do
            if wid == Win then
                runtimeIdx = i
                break
            end
        end
        if runtimeIdx then table.remove(_windows, runtimeIdx) end
        -- Compact DB: remove entry and shift remaining down (no holes). Uses W.idx (not the
        -- winIdx upvalue) since prior deletions may have shifted this window's slot since creation.
        local removedIdx = runtimeIdx or Win.idx
        local cfg = DB()
        if cfg.windows then
            table.remove(cfg.windows, removedIdx)
            cfg.windowCount = #cfg.windows
        end
        -- Update remaining windows' idx to match their new DB position
        for i, wid in ipairs(_windows) do
            wid.idx = i
        end
        -- Re-key unlock anchor/size-match links for the shifted window set and refresh registrations (drops the stale highest EDM_Win slot)
        if CUI.ShiftIndexedAnchorKeys then CUI.ShiftIndexedAnchorKeys("EDM_Win", removedIdx, oldCount) end
        mod.RegisterDMUnlock()
    end

    -- The first paint of a built or re-applied window, a frame later (off the build or
    -- profile swap frame): one per frame however often it is asked for, none while parked.
    local function FirstPaint()
        Win._firstPaintPending = nil
        if Win._parked then return end
        Win.Refresh()
        -- First install: show home page so user can pick a mode
        if not wdb.curDMType then Win.ShowHome() end
    end

    -- Reapply: points this window at slot idx of the profile now active and re-reads
    -- every setting read while it was built above, leaving it as a newly built window
    -- for that slot (a profile swap keeps its windows; a parked window comes back).
    function Win.Reapply(index)
        if Win._parked then
            Win._parked = nil
            CUI.RegisterVisibilityUpdater(Win.UpdateVisibility)
        else
            -- A fresh scan entry, as a new window gets: the cached answer is the old profile's
            CUI.UnregisterMouseoverTarget(widget)
        end
        CUI.RegisterMouseoverTarget(widget, MouseoverActive)
        Win.idx = index
        wdb = WinDB(index)
        local cfg = DB()
        -- Window state, as set at the top of this function
        local dmType = wdb.curDMType or Enum.DamageMeterType.DamageDone
        if not DM_TYPE_NAMES[dmType] then dmType = Enum.DamageMeterType.DamageDone end
        Win.curDMType = dmType
        Win.curSession = wdb.curSession or Enum.DamageMeterSessionType.Current
        Win.curSessionID = nil
        Win.visibleCount = 0
        Win.windowLocked = wdb.locked or false
        Win.snapDisabled = wdb.snapDisabled or false
        Win.sourceClass = nil
        Win.cachedSources = nil
        Win.stickyAtTop = false
        Win.stickyGuard = false
        -- Every paint memo and the cached session: any of their inputs may differ now
        Win._barCacheKey, Win._stickyCacheKey, Win._lastSession, Win._refreshPending = nil, nil, nil, nil
        Win._stickyClassCache, Win._stickySpecCache, Win._stickyRankCache, Win._stickyNameCache =
            nil, nil, nil, nil
        Win._timerSec, Win._fitFull, Win._fitAvail, Win._cachedTargets = nil, nil, nil, nil
        -- A drag or resize in flight ends here
        dragging = false
        dragFrame:Hide()
        Win.resizing = false
        resizeFrame:Hide()
        widget:SetSize(wdb.width or 300, wdb.height or 200)
        -- An unlock-anchored window waits unplaced for its anchor, as a new one does
        widget:ClearAllPoints()
        Win.ApplyPosition()
        -- Home page and breakdown closed, every row empty, scrolled to the top
        Win.HideHome()
        Win.CloseSource()
        for i = 1, BAR_POOL_SIZE do
            local barFrame = Win.rowPool[i]
            barFrame.row:Hide()
            barFrame.classIcon:Hide()
            barFrame._src = nil
            barFrame._srcGUID = nil
            barFrame._class = nil
            barFrame._cachedSlot = nil
            barFrame._cachedClass = false
            barFrame._cachedSpecIcon = nil
            barFrame._cachedColorClass = false
            barFrame._cachedSrcName = nil
            barFrame._cachedDisplayName = nil
            barFrame._cachedAmtText = nil
            barFrame._cachedRank = nil
            barFrame._cachedThreatColor = nil
        end
        local sp = Win.stickyPlayer
        sp.row:Hide()
        sp.classIcon:Hide()
        Win.stickySep:Hide()
        if Win._decorSync then mod.DMSyncRowDecor(Win) end
        sp._src = nil
        sp._srcGUID = nil
        sp._class = nil
        viewport:SetVerticalScroll(0)
        RecalcViewport(0)
        Win.srcViewport:SetVerticalScroll(0)
        _srcScrollMax = 0
        if homeScroll then homeScroll:SetVerticalScroll(0) end
        -- Window and breakdown background, header bar
        local bgR, bgG, bgB, bgA = cfg.bgR or 0, cfg.bgG or 0, cfg.bgB or 0, cfg.bgAlpha or 0.75
        local hdrH = GetHeaderH()
        widget._bg:ClearAllPoints()
        widget._bg:SetPoint("TOPLEFT", widget, "TOPLEFT", 0, -hdrH)
        widget._bg:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", 0, 0)
        mod.DMPaintWindowBg(widget._bg, bgR, bgG, bgB, bgA, true, cfg.bgTexture)
        mod.DMPaintWindowBg(Win.sourceFrame._bg, bgR, bgG, bgB, bgA, nil, cfg.bgTexture)
        header:SetHeight(hdrH)
        local hc = cfg.hdrBgColor
        mod.DMPaintHeaderBg(
            header._hdrBg,
            hc and hc.r or 0x1B / 255,
            hc and hc.g or 0x1B / 255,
            hc and hc.b or 0x1B / 255,
            cfg.hdrBgAlpha or 1
        )
        if not mod.DMClassicSeparator(header._bottomBorder, PhysicalPixels(1)) then
            local size = cfg.hdrBottomBorderSize or 0
            local color = cfg.hdrBottomBorderColor or {}
            header._bottomBorder:SetHeight(PhysicalPixels(size))
            header._bottomBorder:SetColorTexture(color.r or 0, color.g or 0, color.b or 0, color.a or 1)
            header._bottomBorder:SetShown(size > 0 and not mod.DMBlizz())
        end
        -- Title and timer
        local titleFS = cfg.hdrFontSize or 11
        SetDMFont(Win.titleText, titleFS)
        Win.titleText:ClearAllPoints()
        Win.titleText:SetPoint(
            "LEFT",
            header,
            "LEFT",
            6 + (cfg.hdrTextOffX or 0),
            (cfg.hdrTextOffY or 0) + mod.DMHdrLift(cfg.hdrHeight)
        )
        local tR, tG, tB
        if cfg.hdrTextUseAccent ~= false then
            tR, tG, tB = mod.DMTitleRGB()
        else
            local tc = cfg.hdrTextColor
            tR = tc and tc.r or 1
            tG = tc and tc.g or 1
            tB = tc and tc.b or 1
        end
        Win.titleText:SetTextColor(tR, tG, tB, 1)
        Win._fullTitle = Loc("Damage Done")
        Win.titleText:SetText(Win._fullTitle)
        SetDMFont(Win.timerText, titleFS)
        Win.timerText:SetText("(0:00)")
        Win.timerText:SetShown(not wdb.hideTimer)
        -- Header buttons: size, glyph colour, meter type icon, close icon, lock state
        local sz = mod.DMHdrIconSize(cfg)
        local ir, ig, ib = IconColor()
        for _, button in ipairs(Win.hdrBtns) do
            button:SetSize(sz, sz)
        end
        for _, ic in ipairs(Win.hdrIcons) do
            if not ic._hdrArt then ic:SetVertexColor(ir, ig, ib, ICON_ALPHA) end
        end
        mod.DMSetTypeIcon(Win._modeIcon, Win.curDMType)
        local closeTex = Win._closeIconTex
        if closeTex and not closeTex._hdrArt then
            closeTex:ClearAllPoints()
            closeTex:SetSize(sz + 2, sz + 2)
            closeTex:SetPoint("CENTER", Win.winActionBtn, "CENTER", 0, 0)
        end
        LayoutHeaderButtons(Win, cfg, sz)
        PaintLockIcon()
        local a = Win.isHovered and 0.3 or 0
        Win.resizeGrip:SetAlpha(Win.windowLocked and 0 or a)
        Win.lockBtn:SetAlpha(a)
        ApplyHeaderButtonsHoverVisibility(Win, cfg)
        -- Rows and the pinned row: borders, track, text offsets
        for i = 1, BAR_POOL_SIZE do
            local barFrame = Win.rowPool[i]
            barFrame.ApplyBorder()
            barFrame.ApplyIconBorder()
            barFrame.ApplyBg()
            barFrame.ApplyTextOffsets()
        end
        sp.ApplyBorder()
        sp.ApplyIconBorder()
        sp.ApplyBg()
        sp.ApplyTextOffsets()
        Win.UpdateVisibility()
        if not Win._firstPaintPending then
            Win._firstPaintPending = true
            C_Timer.After(0, FirstPaint)
        end
    end

    Win.UpdateVisibility()

    -- Defer initial refresh off the init frame
    Win._firstPaintPending = true
    C_Timer.After(0, FirstPaint)

    if conf.hdrBottomSeparator then mod.DMApplyHeaderSeparator(Win) end
    return Win
end

-- A window for slot idx: a parked window brought back (W.Reapply), else a new one.
-- Slot 1 always gets a window built for it (its header carries New Window), and
-- every parked window was built for a later slot.
function mod.DMAcquireWindow(index)
    local parked = mod._dmParked
    local wid = index ~= 1 and parked[#parked]
    if wid then
        parked[#parked] = nil
        wid.Reapply(index)
        return wid
    end
    return CreateDMWindow(index)
end

Inner.CreateDMWindow = CreateDMWindow
Inner.broken = false
