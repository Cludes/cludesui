if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_RaidFrames_Extras.lua
--
--  The healer mana text display, the player group label and the
--  frame-provider APIs for external trackers.
--  Reads the earlier Raid Frames files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIRaidFrames.lua or an earlier Raid Frames file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local pairs = pairs
local ipairs = ipairs
local type = type
local select = select
local UnitName = UnitName
local UnitClass = UnitClass
local UnitExists = UnitExists
local UnitIsUnit = UnitIsUnit
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local UnitInRaid = UnitInRaid
local GetRaidRosterInfo = GetRaidRosterInfo
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local issecretvalue = issecretvalue
local CreateFrame = CreateFrame
local RAID_CLASS_COLORS = RAID_CLASS_COLORS

local allButtons, GetFFD, GetPowerColor = Inner.allButtons, Inner.GetFFD, Inner.GetPowerColor
local ApplyFont, PixelSnap = Inner.ApplyFont, Inner.PixelSnap

local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(val)
    saved = val
end

-------------------------------------------------------------------------------
--  Healer Mana Text Display (Extras): one text row per group healer, riding
--  the EXISTING per-unit trackers. UpdatePowerEventRegistration keeps
--  UNIT_POWER_UPDATE registered for healers while enabled (same loop, same
--  role reads), the shared OnEvent feeds the rows, and the healer set
--  rebuilds on the same roster/roles cadence. Zero cost while disabled:
--  no rows map (the OnEvent tail is one nil test), no extra registrations,
--  container never built.
-------------------------------------------------------------------------------
do
    local boxHolder
    local rowList = {} -- i -> { nameFS, valFS, unit }

    local function HMSet()
        local prof = saved.profile
        local hm = prof.healerMana
        if not hm then
            hm = { mode = "none" }
            prof.healerMana = hm
        end
        return hm
    end
    mod._HMSet = HMSet

    -- The display's mode gates on the CURRENT group type; solo counts as
    -- neither (the preview eyeball still works ungrouped).
    function mod._HMActive()
        local mode = HMSet().mode or "none"
        if mode == "none" then
            return false
        end
        if IsInRaid() then
            return mode == "raid" or mode == "both"
        end
        if IsInGroup() then
            return mode == "party" or mode == "both"
        end
        return false
    end

    local function EnsureContainer()
        if boxHolder then
            return boxHolder
        end
        boxHolder = CreateFrame("Frame", "ERF_HealerMana", UIParent)
        boxHolder:SetSize(50, 25)
        boxHolder:Hide()
        mod._hmContainer = boxHolder
        local place = HMSet().unlockPos
        if place and place.point then
            boxHolder:SetPoint(
                place.point,
                UIParent,
                place.relPoint or place.point,
                place.x or 0,
                place.y or 0
            )
        else
            boxHolder:SetPoint("CENTER", UIParent, "CENTER", 320, 0)
        end
        return boxHolder
    end
    mod._HMEnsureContainer = EnsureContainer

    -- Value repaint: the engine percent object straight into the display
    -- sink -- secret-safe, no Lua math (same source as the power bars).
    function mod._HMUpdateValue(unitToken)
        local region = mod._hmUnitRows and mod._hmUnitRows[unitToken]
        if not region then
            return
        end
        region.valFS:SetFormattedText("%d", UnitPowerPercent(unitToken, 0, true, CurveConstants.ScaleTo100))
    end

    -- Full rebuild: healer set, names, colors, layout. Runs on the roster/
    -- roles cadence (UpdatePowerEventRegistration tail) + settings changes.
    function mod.HM_Rebuild()
        local hm = HMSet()
        local preview = mod._hmPreview
        if not mod._HMActive() and not preview then
            if boxHolder then
                boxHolder:Hide()
            end
            mod._hmUnitRows = nil
            return
        end
        EnsureContainer()
        local size = hm.textSize or 12
        local spacing = hm.spacing or 2
        local alignR = hm.align == "RIGHT"
        local alignC = hm.align == "CENTER"
        local growUp = hm.growth == "UP"
        local inRaid = IsInRaid()
        local showNames = (hm.showNames ~= false) and (inRaid or preview)
        local classNames = hm.classNames ~= false
        local powerMode = hm.colorMode == "power"
        local cc = hm.color
        local cr, cg, callback = (cc and cc.r) or 1, (cc and cc.g) or 1, (cc and cc.b) or 1
        local fontFile = (CludesUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
        local outline = (CludesUI.GetFontOutlineFlag("raidFrames")) or "OUTLINE"
        local rowH = size + spacing
        local map = {}
        local total, widest = 0, 40

        local function addRow(unitToken, fakeName, fakeClass, fakeVal)
            total = total + 1
            local row = rowList[total]
            if not row then
                row = {
                    nameFS = boxHolder:CreateFontString(nil, "OVERLAY"),
                    valFS = boxHolder:CreateFontString(nil, "OVERLAY"),
                }
                rowList[total] = row
            end
            row.unit = unitToken
            local nameFS, valFS = row.nameFS, row.valFS
            -- The name a font family (other players' names), with no shadow as
            -- the value's plain font.
            CludesUI.SetFontFamily(nameFS, fontFile, size, outline, false)
            valFS:SetFont(fontFile, size, outline)
            -- Value color: power color per unit, or the custom color.
            if powerMode then
                local pr, pg, pb
                if unitToken then
                    pr, pg, pb = GetPowerColor(unitToken)
                end
                valFS:SetTextColor(pr or 0.3, pg or 0.5, pb or 0.85, 1)
            else
                valFS:SetTextColor(cr, cg, callback, 1)
            end
            -- Name first (colors + text), so center alignment can measure it.
            local nameW = 0
            if showNames then
                local nr, ng, nb = cr, cg, callback
                if classNames then
                    local token = fakeClass
                    if not token and unitToken then
                        token = select(2, UnitClass(unitToken))
                        if issecretvalue and issecretvalue(token) then
                            token = nil
                        end
                    end
                    local colour = token
                        and (
                            (CludesUI.GetClassColor(token))
                            or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[token])
                        )
                    if colour then
                        nr, ng, nb = colour.r, colour.g, colour.b
                    end
                elseif powerMode then
                    nr, ng, nb = 1, 1, 1
                end
                nameFS:SetTextColor(nr, ng, nb, 1)
                if fakeName then
                    nameFS:SetText(fakeName)
                else
                    -- Display sink: a secret name renders raw, never inspected.
                    -- The raid frames' Name Format (live names show only in a
                    -- raid).
                    local hmName = unitToken and CludesUI.WithSurname(UnitName(unitToken))
                    if hmName then
                        hmName = mod.RF_FormatName(hmName, saved.profile)
                    end
                    nameFS:SetFormattedText("%s", hmName or "")
                end
                nameFS:Show()
                local wid = nameFS:GetStringWidth()
                if wid and not (issecretvalue and issecretvalue(wid)) then
                    nameW = wid
                else
                    nameW = size * 5 -- secret name: estimated width
                end
            else
                nameFS:SetText("")
                nameFS:Hide()
            end
            -- Fixed value-width estimate: centering on the live value's real
            -- width would shift the row every tick.
            local valEst = size * 2.2
            local rowW = (showNames and (nameW + 4) or 0) + valEst
            if rowW > widest then
                widest = rowW
            end
            -- Growth: rows stack down from the top edge, or up from the
            -- bottom edge (anchor family flips with it).
            local yOff = (growUp and 1 or -1) * (total - 1) * rowH
            local pCorner = growUp and "BOTTOMLEFT" or "TOPLEFT"
            local pCornerR = growUp and "BOTTOMRIGHT" or "TOPRIGHT"
            local pEdge = growUp and "BOTTOM" or "TOP"
            nameFS:ClearAllPoints()
            valFS:ClearAllPoints()
            if alignC then
                if showNames then
                    nameFS:SetPoint(pCorner, boxHolder, pEdge, -rowW / 2, yOff)
                    valFS:SetPoint("LEFT", nameFS, "RIGHT", 4, 0)
                    valFS:SetJustifyH("LEFT")
                else
                    valFS:SetPoint(pEdge, boxHolder, pEdge, 0, yOff)
                    valFS:SetJustifyH("CENTER")
                end
            elseif alignR then
                valFS:SetPoint(pCornerR, boxHolder, pCornerR, 0, yOff)
                valFS:SetJustifyH("RIGHT")
                if showNames then
                    nameFS:SetPoint("RIGHT", valFS, "LEFT", -4, 0)
                end
            else
                if showNames then
                    nameFS:SetPoint(pCorner, boxHolder, pCorner, 0, yOff)
                    valFS:SetPoint("LEFT", nameFS, "RIGHT", 4, 0)
                else
                    valFS:SetPoint(pCorner, boxHolder, pCorner, 0, yOff)
                end
                valFS:SetJustifyH("LEFT")
            end
            if fakeVal then
                valFS:SetFormattedText("%d", fakeVal)
            end
            valFS:Show()
            if unitToken then
                map[unitToken] = row
            end
        end

        if preview then
            addRow(nil, "Thaldris", "PRIEST", 84)
            addRow(nil, "Kaelyra", "SHAMAN", 67)
            addRow(nil, "Morwenn", "DRUID", 92)
        else
            -- Ordered walk, roster order; the role read is the same cached
            -- resolver the power-bar registration uses.
            if inRaid then
                for index = 1, 40 do
                    local unitToken = "raid" .. index
                    if UnitExists(unitToken) and mod._ResolvePowerRole(unitToken) == "HEALER" then
                        addRow(unitToken)
                    end
                end
            else
                if mod._ResolvePowerRole("player") == "HEALER" then
                    addRow("player")
                end
                for index = 1, 4 do
                    local unitToken = "party" .. index
                    if UnitExists(unitToken) and mod._ResolvePowerRole(unitToken) == "HEALER" then
                        addRow(unitToken)
                    end
                end
            end
        end

        -- Retire surplus rows from a previous, larger set.
        for index = total + 1, #rowList do
            rowList[index].nameFS:Hide()
            rowList[index].valFS:Hide()
            rowList[index].unit = nil
        end

        mod._hmUnitRows = (not preview and total > 0) and map or nil
        if total > 0 then
            -- Content-sized, with unlock-mover minimums (50x25).
            boxHolder:SetSize(math.max(widest, 50), math.max(total * rowH - spacing, 25))
            boxHolder:Show()
            -- Seed live values (the event path keeps them current after).
            if not preview then
                for unitToken in pairs(map) do
                    mod._HMUpdateValue(unitToken)
                end
            end
        else
            boxHolder:Hide()
        end
    end

    -- Options preview (eyeball): fake rows at the saved position.
    function mod.HM_SetPreview(on)
        mod._hmPreview = on and true or nil
        mod.HM_Rebuild()
    end
end

-------------------------------------------------------------------------------
--  Player Group Label (Extras): the player's raid group number in its own
--  movable frame.
-------------------------------------------------------------------------------
do
    local widget, events

    local function PGSet()
        local prof = saved.profile
        local pg = prof.playerGroup
        if not pg then
            pg = {}
            prof.playerGroup = pg
        end
        return pg
    end
    mod._PGSet = PGSet

    local function ModeColor(mode, custom)
        if mode == "custom" then
            return custom
        end
        local red, green, blue
        if mode == "class" then
            local classColor = CludesUI.GetClassColor(CludesUI._playerClass)
            if classColor then
                red, green, blue = classColor.r, classColor.g, classColor.b
            end
        else
            red, green, blue = CludesUI.ResolveActiveAccent()
        end
        if not red then
            return custom
        end
        return { r = red, g = green, b = blue, a = 1 }
    end

    local function CustomColor(key)
        local pg, s = PGSet(), saved.profile
        if pg[key] then
            return pg[key]
        end
        if key == "textColor" then
            local gc = s.groupNumberColor or {}
            return { r = gc.r or 1, g = gc.g or 1, b = gc.b or 1, a = gc.a or 0.75 }
        end
        local bc = s.borderColor or {}
        return { r = bc.r or 0, g = bc.g or 0, b = bc.b or 0, a = s.borderAlpha or 1 }
    end
    mod._PGCustomColor = CustomColor

    function mod._PGStyle()
        local pg, s = PGSet(), saved.profile
        local backdrop = s.customBgColor or {}
        return pg.textSize or s.groupNumberSize or 10,
            ModeColor(pg.textColorMode or "accent", CustomColor("textColor")),
            pg.bgColor or {
                r = backdrop.r or 17 / 255,
                g = backdrop.g or 17 / 255,
                b = backdrop.b or 17 / 255,
                a = 1,
            },
            pg.borderSize or s.borderSize or 1,
            ModeColor(pg.borderColorMode or "accent", CustomColor("borderColor"))
    end

    local function ApplyPos()
        if not widget then
            return
        end
        local place = PGSet().unlockPos
        widget:ClearAllPoints()
        if place and place.point then
            widget:SetPoint(place.point, UIParent, place.relPoint or place.point, place.x or 0, place.y or 0)
        else
            widget:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
        end
    end
    mod._PGApplyPos = ApplyPos

    local function EnsureFrame()
        if widget then
            return widget
        end
        widget = CreateFrame("Frame", "ERF_PlayerGroup", UIParent)
        widget:SetSize(50, 25)
        widget:Hide()
        widget.bg = widget:CreateTexture(nil, "BACKGROUND")
        widget.bg:SetAllPoints()
        widget.borderFrame = CreateFrame("Frame", nil, widget)
        widget.borderFrame:SetAllPoints()
        widget.text = widget:CreateFontString(nil, "OVERLAY")
        widget.text:SetPoint("CENTER")
        mod._pgFrame = widget
        ApplyPos()
        return widget
    end
    mod._PGEnsureFrame = EnsureFrame

    local fmt, isShown -- the text format and the group it shows

    local function UpdateGroup()
        if not widget then
            return
        end
        local index = IsInRaid() and UnitInRaid("player")
        local set = index and select(3, GetRaidRosterInfo(index))
        -- Out of a raid, or a roster read mid-update that has no group for you yet.
        if not index or type(set) == "nil" then
            if not mod._pgPreview then
                widget:Hide()
                isShown = nil
                return
            end
            set = 3
        end
        -- A secret subgroup goes straight into the text sink, never compared.
        if issecretvalue and issecretvalue(set) then
            widget.text:SetFormattedText(fmt, set)
            isShown = nil
        elseif set ~= isShown then
            widget.text:SetFormattedText(fmt, set)
            isShown = set
        end
        widget:Show()
    end

    -- Style path: settings changes, reloads and accent changes.
    function mod.PG_Apply()
        local pg = PGSet()
        local on = pg.enabled and true or false
        if on and not events then
            events = CreateFrame("Frame")
            events:SetScript("OnEvent", UpdateGroup)
            CludesUI.RegAccent({ type = "callback", fn = mod.PG_Apply })
        end
        if events then
            if on then
                events:RegisterEvent("GROUP_ROSTER_UPDATE")
            else
                events:UnregisterEvent("GROUP_ROSTER_UPDATE")
            end
        end
        if not on then
            if widget then
                widget:Hide()
            end
            return
        end
        EnsureFrame()
        local size, tc, backdrop, bs, bc = mod._PGStyle()
        local cfg = saved.profile
        local full = pg.format == "full"
        local fontStr = widget.text
        ApplyFont(fontStr, size)
        fontStr:SetTextColor(tc.r, tc.g, tc.b, tc.a or 1)
        fmt = full and GROUP_NUMBER or "%d"
        local wid, hgt = pg.width, pg.height
        if not (wid and hgt) then
            -- The widest group, so the size never changes with the number.
            local tw = 0
            for g = 1, 8 do
                fontStr:SetFormattedText(fmt, g)
                local sw = fontStr:GetStringWidth()
                if sw > tw then
                    tw = sw
                end
            end
            local th = fontStr:GetStringHeight()
            if not full then
                tw = math.max(tw, th)
                th = tw
            end
            local pad = (pg.padding or 4) * 2
            wid = wid or (tw + pad)
            hgt = hgt or (th + pad)
        end
        isShown = nil
        widget:SetSize(PixelSnap(wid), PixelSnap(hgt))
        widget.bg:SetColorTexture(backdrop.r, backdrop.g, backdrop.b, backdrop.a or 1)
        local texture = cfg.borderTexture or "solid"
        -- The frame border's exact pixels apply only at its own size.
        local px = (pg.borderSize == nil) and CludesUI.BorderPx(cfg.borderSizePx, bs, texture) or nil
        CludesUI.ApplyBorderStyle(
            widget.borderFrame,
            bs,
            bc.r,
            bc.g,
            bc.b,
            bc.a or 1,
            texture,
            cfg.borderTextureOffset,
            cfg.borderTextureOffsetY,
            cfg.borderTextureShiftX,
            cfg.borderTextureShiftY,
            "unitframes",
            bs,
            nil,
            px
        )
        UpdateGroup()
    end

    function mod.PG_SetPreview(on)
        mod._pgPreview = on and true or nil
        mod.PG_Apply()
    end
end

mod.GetFFD = GetFFD

-------------------------------------------------------------------------------
--  External tracker integration (frame-provider APIs)
-------------------------------------------------------------------------------
-- Some cooldown/defensive tracker addons anchor icons onto party/raid unit
-- frames, found via a hardcoded addon list or a public provider API. CUI
-- frames are custom, so where a provider API exists we hand it our buttons;
-- the unit lives on the secure "unit" attribute (GetAttribute), so no plain
-- field on the button is needed. Name-scanning trackers (LibGetFrame) match our
-- button names from that library's default priority list, but the match only runs
-- against a frame list it caches (see ns._NotifyTrackerProviders).

-- Currently-visible CUI unit buttons with a unit assigned (party AND raid). Both sets
-- are pre-created once (the startingIndex -4 / Show / 1 trick) and never destroyed or
-- recycled -- the secure header only reassigns "unit" and shows/hides -- so a collected
-- list is exactly as stable for raid as for party; IsVisible + unit is what excludes a
-- button the header has parked.
--
-- Extra frames are skipped (deliberate DUPLICATES of units already on a real raid
-- button -- handing a tracker both leaves it choosing between two frames for one unit).
-- Boss frames never join allButtons for the same reason: not party/raid unit frames.
mod._CollectTrackerFrames = function()
    local result = {}
    local function Collect(entries)
        if not entries then
            return
        end
        for _, button in ipairs(entries) do
            if button:IsVisible() and button:GetAttribute("unit") and not GetFFD(button)._isExtra then
                result[#result + 1] = button
            end
        end
    end
    Collect(mod._partyAllButtons)
    Collect(allButtons)
    return result
end

-- Public unit -> frame lookup for any addon wanting our raid or party frame.
-- LibGetFrame cannot answer on an addon-restricted map: it keeps a cached frame
-- only when UnitIsUnit(frameUnit, target) is non-secret, and that call is
-- SecretWhenUnitComparisonRestricted, so every frame is skipped there however
-- fresh the cache. This compares nothing -- it reads the secure "unit"
-- attribute the header wrote. Extra frames answer last: they duplicate a unit
-- already on a real raid button.
function CludesUI.GetUnitFrame(unitToken)
    if type(unitToken) ~= "string" then
        return nil
    end
    local function Find(entries)
        if not entries then
            return nil
        end
        for _, button in ipairs(entries) do
            if button:IsVisible() then
                local u = button:GetAttribute("unit")
                -- type() reports a secret's underlying type, so a secret
                -- attribute would pass as a string and the compare would throw:
                -- probe for secrecy first, never compare a secret.
                if type(u) == "string" and not (issecretvalue and issecretvalue(u)) then
                    if u == unitToken then
                        return button
                    end
                    -- The header gives the player's own button a raidN token, so
                    -- a literal compare never finds "player". UnitIsUnit answers
                    -- a SECRET boolean for a restricted pairing (or nil when the
                    -- compare is refused); only a plain true counts, and a secret
                    -- is never looked at.
                    if unitToken == "player" then
                        local success, same = pcall(UnitIsUnit, u, "player")
                        if success and not (issecretvalue and issecretvalue(same)) and same == true then
                            return button
                        end
                    end
                end
            end
        end
        return nil
    end
    return Find(mod._partyAllButtons) or Find(allButtons) or mod._xfUnitToButton[unitToken]
end

-- Notifies subscribed providers that our frame set changed, debounced to one
-- refresh per frame. Driven from the visibility paths -- the one change a
-- provider cannot learn from its own roster events.
--
-- LibGetFrame resolves units against a frame list it caches, rebuilt only on its
-- own six events and recording only buttons visible at that instant. Our header
-- set builds lazily and defers combat-time changes to regen, so the cache can
-- miss the whole set with no event left to correct it; consumers then read nil
-- and silently do nothing. ScanForUnitFrames is its public invalidation (queued
-- and time-sliced). Resolved per call, not cached: either provider may load late.
-- Never asked for in combat: the library's walk reads every frame bare and our
-- aura containers deny tainted reads while auras are secret, so a mid-fight
-- scan can drop every CUI frame for the rest of the fight. The library
-- rescans on its own at PLAYER_REGEN_ENABLED, so the regen pass covers it.
mod._NotifyTrackerProviders = function()
    if mod._trackerRefreshPending then
        return
    end
    local callback = mod._trackerRefreshCb
    local lgf = LibStub and LibStub("LibGetFrame-1.0", true)
    if not callback and not (lgf and lgf.ScanForUnitFrames) then
        return
    end
    mod._trackerRefreshPending = true
    C_Timer.After(0, function()
        mod._trackerRefreshPending = false
        if callback then
            pcall(callback)
        end
        if lgf and not InCombatLockdown() then
            pcall(lgf.ScanForUnitFrames)
        end
    end)
end

-- Registers CUI as a frame provider with any installed, supported tracker.
-- Inert when none is present. Called once from OnEnable.
mod._RegisterTrackerProviders = function()
    -- MiniAuras: stable public global MiniAurasApi.v1, created at its file load and so
    -- present by PLAYER_LOGIN whenever MiniAuras is enabled. MiniCCApi is the
    -- pre-rename global (same v1 contract), kept as a fallback for older installs.
    local api = MiniAurasApi or MiniCCApi
    if api and api.v1 and api.v1.RegisterFrameProvider then
        pcall(function()
            api.v1:RegisterFrameProvider({
                Name = "CludesUI",
                GetFrames = mod._CollectTrackerFrames,
                RegisterRefreshFrames = function(callback)
                    mod._trackerRefreshCb = callback
                end,
            })
        end)
    end
end

Inner.broken = false
