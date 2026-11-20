if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_BlizzardSkin_TooltipSkin.lua
--
--  The game tooltip in the CludesUI style, with static popups, context
--  menus, the resurrect glow and the LFG queue popup.
--  Reads CludesUIBlizzardSkin.lua through ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIBlizzardSkin.lua or an earlier CUI_BlizzardSkin_*.lua file
-- failed to load.
if not Inner or Inner.last ~= "main" then
    return
end

local FFD, GetFFD = Inner.FFD, Inner.GetFFD-------------------------------------------------------------------------------
; ------------------------------------------------------------------------------- --  Tooltip / Context Menu / Static Popup Skinning --  Restyles GameTooltip et al in CUI dark style; visual-only (alpha, backdrop color, --  font). NEVER Hide/Show/SetParent Blizzard frames; hooks are hooksecurefunc post-hooks only.
(function()
    local _ttSkinned = {}
    local _isSecret = issecretvalue
    local _PP -- resolved lazily
    local _select = select
    local _GameTooltip = GameTooltip
    local _RAID_CC = RAID_CLASS_COLORS
    local _nameL1 = nil -- cached ref to GameTooltipTextLeft1

    local function _enabled()
        return not CludesUIDB or CludesUIDB.customTooltips ~= false
    end
    -- Popups + context menus reskin. customTooltips governs ONLY the game tooltip; reskinPopupsMenus
    -- is seeded from it once at login then independent. BLIZZARD WINDOW RESKINS (queue popup, game menu, group finder, great vault) are independent of BOTH masters.
    local function _pmEnabled()
        return not CludesUIDB or CludesUIDB.reskinPopupsMenus ~= false
    end

    -- IsForbidden() reports only EXPLICIT marking. A forbidden LAYOUT aspect inherited from
    -- the frame a tooltip or menu is anchored to (Blizzard UI widget owners hand one to the
    -- tooltip they own, on hover) restricts every call on it and on everything anchored
    -- below it without ever setting that flag, so the only legal probe is a pcall'd read.
    -- Skip the pass instead of raising inside a Blizzard OnShow; the last-good skin stands and the next apply, off that anchor, runs normally.
    local function _ttUsable(tip)
        local success, wid = pcall(tip.GetWidth, tip)
        if not success then
            return false
        end
        if _isSecret and _isSecret(wid) then
            return false
        end
        return true
    end

    -- Size step, step key, color and opacity of a <prefix>Border* configured border
    -- colorOverride (optional {r,g,b}): a caller-computed color for loot window's "quality"
    local function _resolveConfiguredBorder(prefixText, legacySize, colorOverride)
        local saved = CludesUIDB or {}
        local key = saved[prefixText .. "BorderThickness"]
        local sizes = { none = 0, thin = 1, normal = 2, heavy = 3, strong = 4 }
        local size = key and (sizes[key] or 1) or (legacySize or 1)
        key = key
            or ({ [0] = "none", [1] = "thin", [2] = "normal", [3] = "heavy", [4] = "strong" })[size]
            or "thin"
        local modeName = saved[prefixText .. "BorderColorMode"] or "custom"
        local color
        if colorOverride then
            color = colorOverride
        elseif modeName == "accent" then
            color = CludesUI.CLUDES_GREEN or { r = 0.27, g = 0.86, b = 0.49 }
        elseif modeName == "class" then
            local _, class = UnitClass("player")
            color = class and RAID_CLASS_COLORS[class] or { r = 1, g = 1, b = 1 }
        else
            color = saved[prefixText .. "BorderColor"] or { r = 1, g = 1, b = 1 }
        end
        local alpha = saved[prefixText .. "BorderOpacity"]
        if alpha == nil then
            alpha = (modeName == "custom") and CludesUI.RESKIN.BRD_ALPHA or 0.5
        end
        return saved, size, key, color, alpha
    end

    local function _applyConfiguredBorder(ownerFrame, prefixText, legacySize, colorOverride)
        if not ownerFrame or not CludesUI.ApplyBorderStyle then
            return
        end
        -- Read the level up front: it is the first widget call this makes, so it doubles as the restriction probe (see _ttUsable).
        local okLvl, ownerLevel = pcall(ownerFrame.GetFrameLevel, ownerFrame)
        if not okLvl then
            return
        end
        local saved, size, key, color, alpha = _resolveConfiguredBorder(prefixText, legacySize, colorOverride)
        local payload = GetFFD(ownerFrame)
        if not payload.configBorder then
            payload.configBorder = CreateFrame("Frame", nil, ownerFrame, "BackdropTemplate")
            payload.configBorder:SetAllPoints(ownerFrame)
            payload.configBorder:EnableMouse(false)
            if not _PP then
                _PP = CludesUI.PP
            end
            if _PP and _PP.HideBorder then
                _PP.HideBorder(ownerFrame)
            end
        end
        -- Recomputed every apply so Show Behind works live. +4 not +5: the resurrect-accept
        -- glow overlay sits at +5 on the same buttons and a tie goes to the later-created sibling, so the border must never bury it.
        payload.configBorder:SetFrameLevel(
            saved[prefixText .. "BorderBehind"] and math.max(0, ownerLevel - 1) or (ownerLevel + 4)
        )
        local texture = saved[prefixText .. "BorderTexture"] or "solid"
        -- Exact Border Size (the <prefix>BorderThicknessPx companion); nil = the legacy step above, unchanged.
        local pixel = CludesUI.BorderPx(saved[prefixText .. "BorderThicknessPx"], size, texture)
        CludesUI.ApplyBorderStyle(
            payload.configBorder,
            size,
            color.r,
            color.g,
            color.b,
            alpha,
            texture,
            saved[prefixText .. "BorderOffsetX"],
            saved[prefixText .. "BorderOffsetY"],
            saved[prefixText .. "BorderShiftX"],
            saved[prefixText .. "BorderShiftY"],
            "blizzardSkin",
            key,
            nil,
            pixel
        )
    end
    CludesUI._applyBlizzardConfiguredBorder = _applyConfiguredBorder

    -- Removes a border drawn by _applyConfiguredBorder for a setting that went back to its default.
    CludesUI._hideBlizzardConfiguredBorder = function(ownerFrame)
        local payload = ownerFrame and FFD[ownerFrame]
        local border = payload and payload.configBorder
        if not border then
            return
        end
        CludesUI.HideBorderStyle(border)
        border:Hide()
    end

    -- Element & Text Color mode. "native" = surfaces keep original coloring (Game Menu header
    -- stays branded green). UNSET resolves to native unless the user had the legacy Accent Colored Elements toggle on, so old choices carry forward with no migration write and a fresh install sees no change.
    local function _elementColorMode()
        local saved = CludesUIDB or {}
        local modeName = saved.popupMenuButtonTextColorMode
        if modeName == nil then
            modeName = saved.accentReskinElements and "accent" or "native"
        end
        return modeName
    end
    CludesUI._getPopupMenuElementMode = _elementColorMode

    local function _getElementColor()
        local saved = CludesUIDB or {}
        local modeName = _elementColorMode()
        if modeName == "custom" then
            local color = saved.popupMenuButtonTextColor or { r = 1, g = 1, b = 1 }
            return color.r, color.g, color.b
        elseif modeName == "class" then
            local _, class = UnitClass("player")
            local c = class and RAID_CLASS_COLORS[class]
            if c then
                return c.r, c.g, c.b
            end
        end
        -- accent AND native both land here; only the Game Menu header calls this unconditionally under native (branded green) -- others gate first.
        local color = CludesUI.CLUDES_GREEN or { r = 0.27, g = 0.86, b = 0.49 }
        return color.r, color.g, color.b
    end
    CludesUI._getPopupMenuButtonTextColor = _getElementColor

    local function _ttSkin(tip, _, isEmbedded)
        if not tip or tip:IsForbidden() or not _enabled() then
            return
        end
        -- Embedded tooltips (EmbeddedItemTooltip, reward block inside a world-quest tooltip) render INSIDE a parent; skip bg/border to avoid a nested-tooltip look.
        if isEmbedded or tip.IsEmbedded then
            return
        end
        if not _ttUsable(tip) then
            return
        end
        if not _PP then
            _PP = CludesUI and CludesUI.PP
        end
        if tip.NineSlice then
            tip.NineSlice:SetAlpha(0)
        end
        if not GetFFD(tip).bg then
            GetFFD(tip).bg = tip:CreateTexture(nil, "BACKGROUND", nil, -8)
            GetFFD(tip).bg:SetAllPoints()
        end
        -- Unified user-customizable background (shared with CUI custom tooltips via GetTooltipBg); re-applied each call so a settings change shows immediately.
        GetFFD(tip).bg:SetColorTexture(CludesUI.GetTooltipBg())
        GetFFD(tip).bg:Show()
        -- Border size/color (Blizz UI Enhanced > Blizzard Tooltip > Border), same reapply-every-call pattern; size 0 hides the border.
        local _, _, _, _, legacySize = CludesUI.GetTooltipBorder()
        _applyConfiguredBorder(tip, "tooltip", legacySize)
    end
    -- The same look for Blizzard's tooltip-like frames that are not GameTooltips
    -- (their window packs call it on show).
    CludesUI._skinBlizzardTooltipFrame = _ttSkin

    local function _ttFonts(tip, startFrom)
        if not tip or tip:IsForbidden() or not _enabled() then
            return
        end
        local fp = CludesUI.GetFontPath("blizzardSkin") or STANDARD_TEXT_FONT
        local ol = CludesUI.GetFontOutlineFlag("blizzardSkin") or ""
        local scale = CludesUIDB and CludesUIDB.tooltipFontScale or 1.0
        local titleSize = math.floor(13 * scale + 0.5)
        local bodySize = math.floor(11 * scale + 0.5)
        -- pcall'd for the same reason as _ttUsable, and this is the first widget call here.
        local okName, label = pcall(tip.GetName, tip)
        if not okName or not label then
            return
        end
        local nLines = tip.NumLines and tip:NumLines() or 30
        -- Font families (lines show players' names, guilds and notes), with no
        -- drop shadow, as the lines' own template font has none. A line already
        -- on the family is left alone.
        local SetFamily = CludesUI.SetFontFamily
        for i = (startFrom or 1), nLines do
            local leftX = _G[label .. "TextLeft" .. i]
            if not leftX then
                break
            end
            SetFamily(leftX, fp, (i == 1) and titleSize or bodySize, ol, false)
            local right = _G[label .. "TextRight" .. i]
            if right then
                SetFamily(right, fp, bodySize, ol, false)
            end
        end
    end

    local _ttRelaying = setmetatable({}, { __mode = "k" })
    local function _ttOnShow(self)
        _ttSkin(self)
        _ttFonts(self)
        -- Re-show to recalc size with the new fonts. Gated on the skin toggle (hook is
        -- uninstallable, must stay zero-cost when off). pcall'd: a tooltip rendering
        -- secret-capable content (e.g. SetSpellByID) denies a tainted re-Show as
        -- forbidden-object access (field-hit via Blizzard_PTRFeedback's tooltip hook,
        -- which Shows the tooltip from secure code with our OnShow hook behind it);
        -- the recalc is optional polish, the font writes above are region-level and legal regardless.
        if _enabled() and not _ttRelaying[self] then
            _ttRelaying[self] = true
            pcall(self.Show, self)
            _ttRelaying[self] = nil
        end
    end

    local function _ttHook(tip)
        if not tip or tip:IsForbidden() or _ttSkinned[tip] then
            return
        end
        _ttSkinned[tip] = true
        tip:HookScript("OnShow", _ttOnShow)
    end

    local function _accentEnabled()
        -- False in native mode so gated surfaces keep their else-branch look (unrecolored/plain white).
        return _elementColorMode() ~= "native"
    end

    -- Unified inspect system: while Show Item Level is active, one INSPECT_READY handler fills the tooltip ilvl cache from every inspect, whoever requested it; the tooltip's own requests are paced below.
    local _ilvlCache = {} -- guid -> { ilvl = number, time = GetTime() }
    local _ilvlCacheTTL = 120
    -- Mount-name cache: short TTL, just enough to survive one hover's refresh ticks so an unmounted player is scanned once, not per tick. name=false means "scanned, none".
    local _mountCache = {} -- guid -> { name = string|false, collected = bool|nil, time = GetTime() }
    local _mountCacheTTL = 3
    local _inspectPendingGUID = nil
    -- Inspect request pacing, one table so this chunk gains a single local. The server
    -- silently drops requests that arrive in a burst, and a dropped one yields no
    -- INSPECT_READY, so Blizzard's inspect window (which only opens on a matching one)
    -- stays shut. Hovering across raid frames used to fire one request per frame.
    -- Timings are tuned from one in-game log; the server's real limits are undocumented.
    local _insp = {
        active = false, -- Show Item Level live: event registered, hooks doing work
        pruneAt = 0, -- next time expired _ilvlCache entries are swept
        lastAny = 0, -- last NotifyInspect from ANY source (ours, Blizzard, other addons)
        lastForeign = 0, -- last NotifyInspect that was not ours
        prevForeign = 0, -- lastForeign before the latest foreign call
        ourAt = -1, -- GetTime() of our own last call; same frame in the hook = ours
        pendingAt = 0, -- when our outstanding tooltip request went out
        dwellGUID = nil, -- latest guid the tooltip wants inspected
        dwellAt = 0, -- when that guid was first requested
        dwellArmed = false, -- one dwell timer at a time
        MIN_GAP = 2, -- seconds a tooltip request keeps clear of the previous one, whoever sent it
        DWELL = 0.9, -- cursor must rest on the same unit this long before we ask; long enough that a
        -- quick hover-then-Inspect never puts our request right before Blizzard's
        FOREIGN_WINDOW = 10, -- another addon polling this recently: stay passive, use its data
        PENDING_TTL = 5, -- our own request counts as lost after this, so a retry is allowed
    }
    -- GUID the visible GameTooltip was last populated for (set by the Unit post-call, cleared on hide); lets the async inspect handler confirm identity before touching it.
    local _tipShownGUID = nil
    -- True when any left line already shows label, so an appended score/ilvl line never duplicates one another Unit post-call produced. Matches label as a plain (non-pattern) substring, so "+" is literal.
    local function _tipHasLine(tip, labelText)
        local nm = tip.GetName and tip:GetName()
        if not nm then
            return false
        end
        local num = tip.NumLines and tip:NumLines() or 0
        for i = 1, num do
            local fontStr = _G[nm .. "TextLeft" .. i]
            local txt = fontStr and fontStr:GetText()
            if txt and not (_isSecret and _isSecret(txt)) and txt:find(labelText, 1, true) then
                return true
            end
        end
        return false
    end

    -- Returns the mount name shown on a unit and whether the LOCAL player has it collected
    -- (true/false, nil if unknown -- e.g. name came from the aura, not MountJournal). Collection state is the 11th return of GetMountInfoByID, per-character.
    local function _getMountedAuraName(unitToken)
        if not unitToken or (_isSecret and _isSecret(unitToken)) then
            return nil
        end
        if not UnitExists(unitToken) or not UnitIsPlayer(unitToken) then
            return nil
        end
        if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
            return nil
        end
        if not (C_MountJournal and C_MountJournal.GetMountFromSpell) then
            return nil
        end
        -- GetAuraDataByIndex hard-errors for tainted callers while auras are
        -- restricted instead of returning nil, so an issecretvalue() check
        -- comes too late -- skip outright (cosmetic addition, not worth the
        -- risk). Gate on the LIVE restriction probe: combat lockdown alone
        -- misses between-pull windows in protected instances AND forced
        -- restriction states, which is exactly where this scan detonated.
        local AK = CludesUI.AuraKit
        if InCombatLockdown() or (AK and AK.AurasRestricted and AK.AurasRestricted()) then
            return nil
        end

        for i = 1, 255 do
            local aura = C_UnitAuras.GetAuraDataByIndex(unitToken, i, "HELPFUL")
            if not aura then
                break
            end
            local spellID = aura.spellId
            if spellID and not (_isSecret and _isSecret(spellID)) then
                local mountID = C_MountJournal.GetMountFromSpell(spellID)
                if mountID and not (_isSecret and _isSecret(mountID)) and mountID > 0 then
                    local label, collected
                    if C_MountJournal.GetMountInfoByID then
                        local mountLabel, _, _, _, _, _, _, _, _, _, isCollected =
                            C_MountJournal.GetMountInfoByID(mountID)
                        if mountLabel and not (_isSecret and _isSecret(mountLabel)) then
                            label = mountLabel
                            if type(isCollected) == "boolean" then
                                collected = isCollected
                            end
                        end
                    end
                    if not label then
                        local auraName = aura.name
                        if auraName and not (_isSecret and _isSecret(auraName)) then
                            label = auraName
                        end
                    end
                    if label and label ~= "" then
                        return label, collected
                    end
                end
            end
        end
        return nil
    end
    -- InspectFrame_Show's NotifyInspect ran just before this post-hook, in the same frame,
    -- and was counted as foreign. It is the user's own inspect, not another addon
    -- polling, so it must not switch the tooltip to passive mode.
    local function _onInspectUnit()
        if _insp.active and _insp.lastForeign == GetTime() then
            _insp.lastForeign = _insp.prevForeign
        end
    end
    -- Caches every INSPECT_READY, including the ones other addons asked for, which is
    -- what lets the tooltip stay passive while such an addon polls the group.
    local _inspectFrame
    local function _onInspectReady(self, _, unitGuid)
        -- Option turned off this session: stop listening; the next unit tooltip with it
        -- on re-activates. Same test as the tooltip pass, so the two never flip-flop
        -- (the reskin master only takes effect on /reload, when nothing is activated).
        if CludesUIDB and CludesUIDB.tooltipItemLevel == false then
            self:UnregisterEvent("INSPECT_READY")
            _insp.active = false
            return
        end
        if not unitGuid or (_isSecret and _isSecret(unitGuid)) then
            return
        end
        if unitGuid == _inspectPendingGUID then
            _inspectPendingGUID = nil
        end
        -- Read item level through a token derived from THAT GUID, so it is captured even after the cursor left the unit and cached under the right GUID.
        if C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel and _G.UnitTokenFromGUID then
            local u = _G.UnitTokenFromGUID(unitGuid)
            if u and not (_isSecret and _isSecret(u)) and UnitExists(u) then
                local value = C_PaperDollInfo.GetInspectItemLevel(u)
                if value and not (_isSecret and _isSecret(value)) and value > 0 then
                    -- One request fires a burst of 10+ events; update in place instead of allocating per event.
                    local record = _ilvlCache[unitGuid]
                    local nowTime = GetTime()
                    if record then
                        record.ilvl = math.floor(value)
                        record.time = nowTime
                    else
                        -- Every inspect source feeds the cache now, so sweep expired
                        -- entries at most once per TTL, only when a new one is added.
                        if nowTime >= _insp.pruneAt then
                            _insp.pruneAt = nowTime + _ilvlCacheTTL
                            for g, entry in pairs(_ilvlCache) do
                                if (nowTime - entry.time) >= _ilvlCacheTTL then
                                    _ilvlCache[g] = nil
                                end
                            end
                        end
                        _ilvlCache[unitGuid] = { ilvl = math.floor(value), time = nowTime }
                    end
                end
            end
        end
        -- Append only while the tooltip still shows this GUID and the line is not already present.
        local cachedValue = _ilvlCache[unitGuid]
        local ttd = GetFFD(_GameTooltip)
        if
            cachedValue
            and _GameTooltip:IsShown()
            and _tipShownGUID == unitGuid
            and not ttd.ilvlShown
            and not _tipHasLine(_GameTooltip, CludesUI.L("Item Level"))
        then
            local nBefore = _GameTooltip:NumLines() or 0
            _GameTooltip:AddDoubleLine(CludesUI.L("Item Level:"), cachedValue.ilvl, 1, 1, 1, 1, 1, 1)
            _ttFonts(_GameTooltip, nBefore + 1)
            -- Runs for every source's result, also in combat; pcall'd like the re-Show in
            -- _ttOnShow, since a tainted re-Show can be denied as forbidden access.
            pcall(_GameTooltip.Show, _GameTooltip)
            ttd.ilvlShown = true
        end
    end
    -- Built and registered only while Show Item Level is on (from _ttInitData at login,
    -- or from the first unit tooltip after it is turned back on), so with it or the
    -- tooltip reskin off after a /reload nothing is registered, hooked or created.
    -- hooksecurefunc cannot be undone: after a mid-session toggle-off the hook returns
    -- at once. Passive mode starts only once another addon's request is actually seen;
    -- the first request just waits MIN_GAP, so it cannot land inside that polling.
    _insp.Activate = function()
        if _insp.active then
            return
        end
        _insp.active = true
        _insp.lastAny = GetTime()
        if not _inspectFrame then
            _inspectFrame = CreateFrame("Frame")
            _inspectFrame:SetScript("OnEvent", _onInspectReady)
            -- Every inspect request passes here, whoever sent it. A call is ours when it
            -- happens in the frame we stamped (GetTime() is fixed per frame), so a call
            -- that raised can never leave a stuck "ours" flag behind.
            hooksecurefunc("NotifyInspect", function()
                if not _insp.active then
                    return
                end
                local t = GetTime()
                _insp.lastAny = t
                if _insp.ourAt ~= t then
                    _insp.prevForeign = _insp.lastForeign
                    _insp.lastForeign = t
                end
            end)
            if InspectUnit then
                hooksecurefunc("InspectUnit", _onInspectUnit)
            end
        end
        _inspectFrame:RegisterEvent("INSPECT_READY")
    end
    -- Exposed on CludesUI; nothing outside this file reads it today.
    CludesUI._inspectCache = _ilvlCache

    -- Re-derive a CLEAN literal group unit token for a GUID by matching it against
    -- tokens we build ourselves (player/raidN/partyN). On secure raid-frame unit
    -- tooltips, GetUnit()/UnitTokenFromGUID can return a secret/unusable token even
    -- though the GUID is clean, starving token-based APIs (M+ summary, inspect item level); a literal token built here is never secret.
    local function _CleanTokenForGUID(unitGuid)
        if not unitGuid or (_isSecret and _isSecret(unitGuid)) then
            return nil
        end
        if UnitGUID("player") == unitGuid then
            return "player"
        end
        if IsInRaid() then
            for i = 1, GetNumGroupMembers() do
                local tk = "raid" .. i
                local tg = UnitGUID(tk)
                if tg and not (_isSecret and _isSecret(tg)) and tg == unitGuid then
                    return tk
                end
            end
        else
            for i = 1, GetNumSubgroupMembers() do
                local tk = "party" .. i
                local tg = UnitGUID(tk)
                if tg and not (_isSecret and _isSecret(tg)) and tg == unitGuid then
                    return tk
                end
            end
        end
        return nil
    end

    -- Hard blocks for a tooltip request, checked before the dwell and again in it: the
    -- inspect window is open or waiting on this player, or the talent frame is inspecting
    -- someone (ClearInspectPlayer would retarget it). Timed hold-offs, passive mode
    -- included, are not blocks; _dwellTick waits them out.
    local function _inspBlocked(unitGuid, nowTime)
        local psf = PlayerSpellsFrame
        if psf and psf.IsInspecting and psf:IsInspecting() then
            return true
        end
        local frame = InspectFrame
        if frame then
            if frame:IsShown() then
                return true
            end
            -- Blizzard keeps .unit on a window that never opened and shows it on any
            -- later matching INSPECT_READY, so never ask for that person ourselves.
            local u = frame.unit
            if u and not (_isSecret and _isSecret(u)) then
                local g = UnitGUID(u)
                if g and not (_isSecret and _isSecret(g)) and g == unitGuid then
                    return true
                end
            end
        end
        return false
    end
    -- Tooltip-side inspect request, paced. It never fires straight out of the tooltip
    -- pass: a dwell timer runs first, so sweeping the cursor across raid frames costs
    -- one request instead of one per frame. It then yields to the shared request
    -- budget, and asks for no group member while another addon is polling the group --
    -- the INSPECT_READY handler caches whatever that addon asked for, so in a raid
    -- with such an addon running the tooltip adds requests only for non-members.
    -- The price is that an uncached player's item level appears a moment later.
    -- One named timer function, rescheduled while needed, so no closure per hover.
    local function _dwellTick()
        _insp.dwellArmed = false
        local unitGuid = _insp.dwellGUID
        if not unitGuid then
            return
        end
        local saved = CludesUIDB
        -- Cursor moved on, option turned off, or combat started: drop it; the next tooltip pass re-arms.
        if
            _tipShownGUID ~= unitGuid
            or not _GameTooltip:IsShown()
            or not (saved and saved.tooltipItemLevel ~= false)
            or InCombatLockdown()
        then
            _insp.dwellGUID = nil
            return
        end
        local nowTime = GetTime()
        local cachedValue = _ilvlCache[unitGuid]
        if cachedValue and (nowTime - cachedValue.time) < _ilvlCacheTTL then
            _insp.dwellGUID = nil
            return
        end
        if _inspBlocked(unitGuid, nowTime) then
            _insp.dwellGUID = nil
            return
        end
        -- Timing gates only postpone: wait for the dwell, the gap after anyone's last
        -- request (the user's own Inspect included), and our outstanding request's expiry.
        -- Raid frames never refresh their tooltip, so a dropped hover would stay blank.
        local readyAt = math.max(_insp.dwellAt + _insp.DWELL, _insp.lastAny + _insp.MIN_GAP)
        if unitGuid == _inspectPendingGUID then
            readyAt = math.max(readyAt, _insp.pendingAt + _insp.PENDING_TTL)
        end
        -- Passive mode: a group member waits out another addon's polling, which will
        -- inspect them and feed the open tooltip through the handler. Anyone outside the
        -- group is never polled by it, so they keep the plain MIN_GAP pacing.
        local unitToken = _CleanTokenForGUID(unitGuid)
        if unitToken then
            readyAt = math.max(readyAt, _insp.lastForeign + _insp.FOREIGN_WINDOW)
        end
        if readyAt > nowTime then
            _insp.dwellArmed = true
            C_Timer.After(readyAt - nowTime, _dwellTick)
            return
        end
        _insp.dwellGUID = nil
        if not unitToken and _G.UnitTokenFromGUID then
            local tu = _G.UnitTokenFromGUID(unitGuid)
            if tu and not (_isSecret and _isSecret(tu)) then
                unitToken = tu
            end
        end
        -- Same last resort as _resolveTipIdentity: "mouseover" only when it provably maps to this guid.
        if not unitToken and UnitExists("mouseover") then
            local mg = UnitGUID("mouseover")
            if mg and not (_isSecret and _isSecret(mg)) and mg == unitGuid then
                unitToken = "mouseover"
            end
        end
        if not unitToken or not UnitExists(unitToken) or not CanInspect(unitToken) then
            return
        end
        _inspectPendingGUID = unitGuid
        _insp.pendingAt = nowTime
        _insp.ourAt = nowTime
        ClearInspectPlayer()
        NotifyInspect(unitToken)
    end
    -- Caller has already found no cached item level for guid.
    local function _requestTooltipInspect(unitGuid)
        -- The pending dwell re-checks every gate itself; skip them on each refresh meanwhile.
        if _insp.dwellArmed and _insp.dwellGUID == unitGuid then
            return
        end
        local nowTime = GetTime()
        -- Hard-blocked now: arm nothing; a later tooltip refresh or re-hover asks again.
        if _inspBlocked(unitGuid, nowTime) then
            return
        end
        -- Always track the latest unit; a running timer picks up the retarget.
        if _insp.dwellGUID ~= unitGuid then
            _insp.dwellGUID = unitGuid
            _insp.dwellAt = nowTime
        end
        if not _insp.dwellArmed then
            _insp.dwellArmed = true
            C_Timer.After(_insp.DWELL, _dwellTick)
        end
    end

    -- Resolve who this unit tooltip was populated for. SetUnit(u) stamps u's GUID into
    -- data.guid before this post-call runs, so data.guid is the authoritative identity,
    -- correct on the very first hover. The cursor-focus "mouseover" token is NOT trusted
    -- for identity: the secure focus system updates it on its own schedule and can still
    -- point at the previous frame's unit on fast movement/first hover. Returns (guid,
    -- token); token always maps to guid, used only by token-based APIs (class fallback, M+ summary, inspect). Either may be nil; callers then skip our extras.
    local function _resolveTipIdentity(tip, payload)
        local unitGuid = payload and payload.guid
        if unitGuid and _isSecret and _isSecret(unitGuid) then
            unitGuid = nil
        end
        local token
        local success, _, u = pcall(tip.GetUnit, tip)
        if success and u and not (_isSecret and _isSecret(u)) and UnitExists(u) then
            local g = UnitGUID(u)
            if g and not (_isSecret and _isSecret(g)) then
                if not unitGuid then
                    unitGuid = g
                end
                if g == unitGuid then
                    token = u
                end
            end
        end
        -- Covers our raid/party frames, where GetUnit()/UnitTokenFromGUID return secret tokens but the GUID is clean.
        if unitGuid and not token then
            token = _CleanTokenForGUID(unitGuid)
        end
        if unitGuid and not token and _G.UnitTokenFromGUID then
            local tu = _G.UnitTokenFromGUID(unitGuid)
            if tu and not (_isSecret and _isSecret(tu)) and UnitExists(tu) then
                token = tu
            end
        end
        -- Last resort: accept "mouseover" ONLY when it provably maps to the same authoritative
        -- guid -- recovers a usable token (M+/ilvl/title) where UnitTokenFromGUID returns secret, with no cursor-lag misattribution risk.
        if unitGuid and not token and UnitExists("mouseover") then
            local mg = UnitGUID("mouseover")
            if mg and not (_isSecret and _isSecret(mg)) and mg == unitGuid then
                token = "mouseover"
            end
        end
        return unitGuid, token
    end

    -- "Targeting" line: who the hovered unit targets. Opt-in (default off). Needs a
    -- live unit token to build the relational target token, so hovers resolving only
    -- a GUID (our raid/party frames) skip it; identity-secret targets are skipped
    -- entirely. Refresh passes re-run the postprocessor while the tip is up, so an existing line is updated IN PLACE (never appended twice).
    local function _ttTargetLine(tip, unitToken)
        local saved = CludesUIDB
        if not (unitToken and saved and saved.tooltipShowTarget) then
            return
        end
        local tu = unitToken .. "target"
        if C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret then
            local s = C_Secrets.ShouldUnitIdentityBeSecret(tu)
            if (_isSecret and _isSecret(s)) or s == true then
                return
            end
        end
        local labelText = CludesUI.L("Targeting:")
        local tName, red, green, blue
        if UnitExists(tu) then
            if UnitIsUnit(tu, "player") then
                tName = CludesUI.L("You")
                red, green, blue = 0.1, 1, 0.1
            else
                local num = UnitName(tu)
                if num and not (_isSecret and _isSecret(num)) then
                    tName = num
                    red, green, blue = 0.9, 0.9, 0.9
                    if UnitIsPlayer(tu) then
                        local _, castFrame = UnitClass(tu)
                        local classColor = castFrame
                            and not (_isSecret and _isSecret(castFrame))
                            and _RAID_CC
                            and _RAID_CC[castFrame]
                        if classColor then
                            red, green, blue = classColor.r, classColor.g, classColor.b
                        end
                    else
                        local reaction = UnitReaction and UnitReaction(tu, "player")
                        local fc = reaction
                            and not (_isSecret and _isSecret(reaction))
                            and FACTION_BAR_COLORS
                            and FACTION_BAR_COLORS[reaction]
                        if fc then
                            red, green, blue = fc.r, fc.g, fc.b
                        end
                    end
                end
            end
        end
        for i = 2, (tip.NumLines and tip:NumLines() or 0) do
            local lineL = _G["GameTooltipTextLeft" .. i]
            local txt = lineL and lineL:GetText()
            if txt and not (_isSecret and _isSecret(txt)) and txt == labelText then
                local lineR = _G["GameTooltipTextRight" .. i]
                if lineR then
                    if tName then
                        lineR:SetText(tName)
                        lineR:SetTextColor(red, green, blue)
                    else
                        -- Target dropped mid-hover: blank the value, keep the row.
                        lineR:SetText("-")
                        lineR:SetTextColor(0.6, 0.6, 0.6)
                    end
                end
                return
            end
        end
        if tName then
            tip:AddDoubleLine(labelText, tName, 1, 1, 1, red, green, blue)
        end
    end

    -- Hovered player's buffs as icons on the tooltip (opt-in, tooltipShowBuffs).
    -- One engine aura container on GameTooltip, built on first use; the unit is
    -- re-bound only when the hovered GUID changes.
    local _ttBuffs, _ttBuffsGUID, _ttBuffsUnit
    -- position = { container point, tooltip point, growthH, growthV, x, y }
    local _TT_BUFF_POS = {
        bottom = { "TOPLEFT", "BOTTOMLEFT", "Right", "Down", 0, -2 },
        top = { "BOTTOMLEFT", "TOPLEFT", "Right", "Up", 0, 2 },
        left = { "TOPRIGHT", "TOPLEFT", "Left", "Down", -2, 0 },
        right = { "TOPLEFT", "TOPRIGHT", "Right", "Down", 2, 0 },
    }
    local function _ttBuffsLayout()
        local c = _ttBuffs
        if not c then
            return
        end
        local AK = CludesUI.AuraKit
        local saved = CludesUIDB or {}
        if not saved.tooltipShowBuffs then
            c:Hide()
            return
        end
        local size = saved.tooltipBuffSize or 20
        local perRow = saved.tooltipBuffsPerRow or 8
        local p = _TT_BUFF_POS[saved.tooltipBuffPosition or "bottom"] or _TT_BUFF_POS.bottom
        local style = AK.styles.ttBuffs
        -- Only a size change restyles, and through the deferred restyle: the
        -- tooltip can be built from tainted code (a unit frame hover) while
        -- auras are secret, when the engine's aura buttons refuse tainted calls,
        -- and the deferred pass holds the restyle until that lifts.
        if style.width ~= size or style.height ~= size then
            style.width, style.height = size, size
            AK.RestyleSoon("ttBuffs")
        end
        c:SetAuraGroupLayout(
            "buffs",
            { elementWidth = size, elementHeight = size, elementSpacing = 2, lineSpacing = 2 }
        )
        AK.SetContainerRowWidth(c, perRow * size + (perRow - 1) * 2 + 0.4)
        c:ClearAllPoints()
        c:SetPoint(
            p[1],
            _GameTooltip,
            p[2],
            p[5] + (saved.tooltipBuffOffsetX or 0),
            p[6] + (saved.tooltipBuffOffsetY or 0)
        )
        AK.SetContainerAnchor(c, p[1])
        local FD = AnchorUtil.FlowDirection
        AK.SetContainerGrowth(c, FD[p[3]], FD[p[4]])
    end
    CludesUI._applyTooltipBuffs = _ttBuffsLayout

    local function _ttShowBuffs(unitGuid, unitToken)
        local saved = CludesUIDB
        if not (unitToken and saved and saved.tooltipShowBuffs) then
            return
        end
        local AK = CludesUI.AuraKit
        if not _ttBuffs then
            -- noTooltips: no hover tooltips (they would take over GameTooltip);
            -- AuraKit keeps the buttons mouse-free through every restyle. Built
            -- at the saved size, so the buttons are decorated in the engine's
            -- creation window and the first show needs no restyle.
            local size = saved.tooltipBuffSize or 20
            AK.styles.ttBuffs = {
                width = size,
                height = size,
                iconCrop = true,
                hideDurationText = true,
                noTooltips = true,
                border = { 0, 0, 0, 1, size = 1 },
            }
            local c =
                AK.CreateContainerShell(_GameTooltip, { point = { "TOPLEFT", _GameTooltip, "BOTTOMLEFT" } })
            -- Capped at 16 icons.
            AK.AddGroupToContainer(c, {
                key = "buffs",
                filter = { "HELPFUL" },
                maxFrameCount = 16,
                style = "ttBuffs",
                layout = {
                    elementWidth = size,
                    elementHeight = size,
                    elementSpacing = 2,
                    lineSpacing = 2,
                },
            })
            _ttBuffs = c
            _ttBuffsLayout()
            -- Cleared on every tooltip rebuild; the unit post-call re-shows it for players.
            _GameTooltip:HookScript("OnTooltipCleared", function()
                c:Hide()
            end)
            _GameTooltip:HookScript("OnHide", function()
                _ttBuffsGUID = nil
            end)
        end
        if unitGuid ~= _ttBuffsGUID or unitToken ~= _ttBuffsUnit then
            _ttBuffsGUID, _ttBuffsUnit = unitGuid, unitToken
            _ttBuffs:SetUnit(unitToken)
            _ttBuffs:UpdateAllAuras()
        end
        _ttBuffs:Show()
    end

    -- Tooltip Extras level/guild/spec/faction lines: level number by difficulty, a compact
    -- level line, spec/class line in class color, Alliance/Horde line in faction color, and a
    -- guildmate's guild line in guild chat color. Secret text is left as Blizzard drew it.
    local _FACTION_CC = {
        [FACTION_HORDE] = PLAYER_FACTION_COLORS[0],
        [FACTION_ALLIANCE] = PLAYER_FACTION_COLORS[1],
    }
    -- Compact level line labels, colored like the target frame's portrait dragon.
    local _CLASSIFICATION = {
        elite = { ELITE, NORMAL_FONT_COLOR },
        rare = { MAP_LEGEND_RARE, LIGHTGRAY_FONT_COLOR },
        rareelite = { MAP_LEGEND_RAREELITE, LIGHTGRAY_FONT_COLOR },
        worldboss = { BOSS, RED_FONT_COLOR },
    }
    -- Level line patterns, anchored at the start, built from the client's own level format
    -- strings so they match in every locale ("Level %s" -> "^Level .-"). The anchor and the
    -- required number (or "??") keep a title like "Leveling Coach" from matching.
    local _LEVEL_PATTERNS = {}
    for _, fmt in ipairs({
        TOOLTIP_UNIT_LEVEL,
        TOOLTIP_UNIT_LEVEL_RACE,
        TOOLTIP_UNIT_LEVEL_TYPE,
        UNIT_TYPE_LEVEL_TEMPLATE,
        UNIT_TYPE_PLUS_LEVEL_TEMPLATE,
        UNIT_LETHAL_LEVEL_TEMPLATE,
        UNIT_TYPE_LETHAL_LEVEL_TEMPLATE,
    }) do
        if fmt:gsub("%%%d?%$?[sd]", ""):find("[^%s%p]") then
            -- Escape the magic characters, then turn the (now escaped) %s / %d / %1$s into ".-".
            local pat = "^" .. fmt:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("%%%%%d?%%?%$?[sd]", ".-")
            _LEVEL_PATTERNS[#_LEVEL_PATTERNS + 1] = pat
        end
    end
    local function _isLevelText(textValue)
        if not textValue:find("[%d%?]") then
            return false
        end
        for _, pat in ipairs(_LEVEL_PATTERNS) do
            if textValue:find(pat) then
                return true
            end
        end
        return false
    end
    -- The guild line is the guild name, optionally followed by "-Realm", " (Rank)" or
    -- Guild Rank's " [Rank]"; matching the start keeps a guild named "Or" off "Level 80 Orc".
    local function _isGuildText(textValue, guildName)
        if textValue:sub(1, #guildName) ~= guildName then
            return false
        end
        local rest = textValue:sub(#guildName + 1)
        local two = rest:sub(1, 2)
        return rest == "" or rest:sub(1, 1) == "-" or two == " (" or two == " ["
    end
    -- One parts list for the compact level line, refilled on every build.
    local _compactParts = {}
    local function _ttLineColors(tip, payload, unitToken, classColor)
        local saved = CludesUIDB
        -- Forever: a hidden ("??") player level the PvP feature knows. Looked up first so
        -- it is written in even when none of the tooltip colour options is on.
        local knownLevel = unitToken and CludesUI.KnownHiddenLevel and CludesUI.KnownHiddenLevel(unitToken)
        if
            not (
                saved
                and (
                    knownLevel
                    or saved.tooltipLevelColor
                    or saved.tooltipClassLineColor
                    or saved.tooltipFactionColor
                    or saved.tooltipGuildmateColor
                    or saved.tooltipCompactLevel
                )
            )
        then
            return
        end
        local guildName = unitToken and GetGuildInfo(unitToken)
        if guildName and _isSecret and _isSecret(guildName) then
            guildName = nil
        end
        local nLines = tip.NumLines and tip:NumLines() or 0
        -- Level line: the tooltip data's UnitLevel line type when the client tags it, else the
        -- first of lines 2-4 (after name, guild or title) that matches a level format.
        local levelIdx
        for _, ld in ipairs(payload and payload.lines or {}) do
            local t = ld.type
            if not (_isSecret and _isSecret(t)) and t == Enum.TooltipDataLineType.UnitLevel then
                levelIdx = ld.lineIndex
                break
            end
        end
        if not levelIdx then
            for i = 2, math.min(nLines, 4) do
                local textValue = _G["GameTooltipTextLeft" .. i]:GetText()
                if
                    textValue
                    and not (_isSecret and _isSecret(textValue))
                    and not (guildName and _isGuildText(textValue, guildName))
                    and _isLevelText(textValue)
                then
                    levelIdx = i
                    break
                end
            end
        end
        -- Difficulty color on every unit, friendly included; battle pet levels aren't
        -- comparable to the player's, so pets keep Blizzard's line.
        local hex, compact
        -- Forever: a hidden player level the PvP feature knows replaces the "??".
        local known = levelIdx and knownLevel
        if
            levelIdx
            and unitToken
            and (saved.tooltipLevelColor or saved.tooltipCompactLevel)
            and not (UnitIsWildBattlePet(unitToken) or UnitIsBattlePetCompanion(unitToken))
        then
            local lvl = known or UnitEffectiveLevel(unitToken)
            local red, green, blue
            if saved.tooltipLevelColor then
                red, green, blue = CludesUI.GetLevelColor(unitToken, lvl, true)
            end
            if red then
                hex = CludesUI.ColorText("%0", red, green, blue)
            end
            -- Compact line: "90 Tauren" for players, "90 Elite Humanoid" for NPCs.
            local player = UnitIsPlayer(unitToken)
            if saved.tooltipCompactLevel and not (_isSecret and (_isSecret(lvl) or _isSecret(player))) then
                local parts = _compactParts
                wipe(parts)
                parts[1] = CludesUI.ColorText(lvl > 0 and lvl or "??", red, green, blue)
                if player then
                    parts[2] = UnitRace(unitToken)
                else
                    local cl = _CLASSIFICATION[UnitClassification(unitToken)]
                    if cl then
                        parts[#parts + 1] = cl[2]:WrapTextInColorCode(cl[1])
                    end
                    parts[#parts + 1] = UnitCreatureType(unitToken)
                end
                local secret = false
                for _, v in ipairs(parts) do
                    if _isSecret and _isSecret(v) then
                        secret = true
                    end
                end
                if not secret then
                    compact = table.concat(parts, " ")
                end
            end
        end
        local doClass = levelIdx and unitToken and classColor and saved.tooltipClassLineColor
        local guildColor = guildName
            and saved.tooltipGuildmateColor
            and UnitIsInMyGuild(unitToken)
            and ChatTypeInfo.GUILD
        if not (hex or compact or known or doClass or guildColor or saved.tooltipFactionColor) then
            return
        end
        for i = 2, nLines do
            local line = _G["GameTooltipTextLeft" .. i]
            local textValue = line and line:GetText()
            if textValue and not (_isSecret and _isSecret(textValue)) then
                if i == levelIdx then
                    -- Compact rewrite, else color the number (or "??") only, leaving text
                    -- another addon already colored.
                    if compact then
                        line:SetText(compact)
                    else
                        local newText, changed = textValue, false
                        if known then
                            local n
                            newText, n = newText:gsub("%?%?", tostring(known), 1)
                            changed = n > 0
                        end
                        if hex and not string.find(newText, "|c", 1, true) then
                            local coloured, num = newText:gsub("%d+", hex, 1)
                            if num == 0 then
                                coloured, num = newText:gsub("%?%?", hex, 1)
                            end
                            if num > 0 then
                                newText, changed = coloured, true
                            end
                        end
                        if changed then
                            line:SetText(newText)
                        end
                    end
                elseif
                    guildColor
                    and (not levelIdx or i < levelIdx)
                    and _isGuildText(textValue, guildName)
                then
                    line:SetTextColor(guildColor.r, guildColor.g, guildColor.b)
                    guildColor = nil
                elseif _FACTION_CC[textValue] then
                    if saved.tooltipFactionColor then
                        local fc = _FACTION_CC[textValue]
                        line:SetTextColor(fc.r, fc.g, fc.b)
                    end
                -- The spec/class line directly follows the level line on player tooltips.
                elseif doClass and i == levelIdx + 1 and textValue ~= PVP_ENABLED then
                    line:SetTextColor(classColor.r, classColor.g, classColor.b)
                end
            end
        end
    end

    local function _ttUnitColor(tip, payload)
        if tip ~= _GameTooltip or tip:IsForbidden() then
            return
        end
        local nLinesBefore = tip.NumLines and tip:NumLines() or 0
        -- Identity comes from the tooltip's own SetUnit data pass (data.guid), never the cursor-focus token, so it never lags to the previous frame.
        local unitGuid, unitToken = _resolveTipIdentity(tip, payload)
        -- Record who this render is for (so a late INSPECT_READY can confirm the tooltip still shows this person) and reset the ilvl marker, before any early return.
        _tipShownGUID = unitGuid
        local ttd = GetFFD(tip)
        ttd.ilvlShown = false
        if not unitGuid then
            return
        end
        -- Class and plain name from the authoritative GUID, with a live-token fallback. Non-players get no additions (GetPlayerInfoByGUID returns no class for non-player GUIDs, matching stock hover).
        local classFile, pname, prealm
        if GetPlayerInfoByGUID then
            local _, eClass, _, _, _, num, region = GetPlayerInfoByGUID(unitGuid)
            if eClass and not (_isSecret and _isSecret(eClass)) then
                classFile, pname, prealm = eClass, num, region
            end
        end
        if not classFile and unitToken then
            if not UnitIsPlayer(unitToken) then
                -- No class additions on non-players, but Targeting still applies (checking a boss's target is the core case).
                _ttLineColors(tip, payload, unitToken)
                _ttTargetLine(tip, unitToken)
                _ttFonts(tip, nLinesBefore)
                return
            end
            local _, castFrame = UnitClass(unitToken)
            if castFrame and not (_isSecret and _isSecret(castFrame)) then
                classFile = castFrame
                pname, prealm = UnitName(unitToken)
            end
        end
        if not classFile then
            return
        end
        if not _nameL1 then
            _nameL1 = _G.GameTooltipTextLeft1
        end
        if not _nameL1 then
            return
        end
        local saved = CludesUIDB
        -- Title hiding is default (tooltipPlayerTitles is opt-in). Rewrite line 1 ONLY when a title is genuinely present, so the no-title case never clobbers foreign line-1 formatting.
        if not (saved and saved.tooltipPlayerTitles) and pname and not (_isSecret and _isSecret(pname)) then
            local display = (prealm and prealm ~= "") and (pname .. "-" .. prealm) or pname
            local current = _nameL1:GetText()
            -- Line 1 carries a title (or other decoration) when it differs from the plain name.
            -- With a clean token, confirm via UnitPVPName so an equivalent plain-name form is never rewritten; without one (our raid/party frames, secret token, GUID-only) fall back to the name-difference check.
            if current and not (_isSecret and _isSecret(current)) and current ~= display then
                local topStrip
                if unitToken and UnitPVPName then
                    local titled = UnitPVPName(unitToken)
                    topStrip = titled and not (_isSecret and _isSecret(titled)) and titled ~= pname
                else
                    topStrip = true
                end
                if topStrip then
                    _nameL1:SetText(display)
                end
            end
        end
        -- Away/busy tag after the name, in Blizzard's own <Away>/<Busy> wording.
        if unitToken and saved and saved.tooltipAFKTag then
            local afk, dnd = UnitIsAFK(unitToken), UnitIsDND(unitToken)
            local tag = not (_isSecret and (_isSecret(afk) or _isSecret(dnd)))
                and (afk and CHAT_FLAG_AFK or dnd and CHAT_FLAG_DND)
            local current = tag and _nameL1:GetText()
            if
                current
                and not (_isSecret and _isSecret(current))
                and not string.find(current, tag, 1, true)
            then
                _nameL1:SetText(current .. " " .. GRAY_FONT_COLOR:WrapTextInColorCode(tag))
            end
        end
        -- Recolor only (never replaces text): name line + health bar.
        local classColor = _RAID_CC and _RAID_CC[classFile]
        if classColor then
            _nameL1:SetTextColor(classColor.r, classColor.g, classColor.b)
            if GameTooltipStatusBar then
                GameTooltipStatusBar:SetStatusBarColor(classColor.r, classColor.g, classColor.b)
            end
        end
        _ttLineColors(tip, payload, unitToken, classColor)
        -- Guild rank next to guild name: Name-Realm [Rank]. Re-found every call (index varies
        -- per unit; titles shift it, so a cached index would decorate the wrong row). Deduped like the M+ line against refresh re-runs.
        if unitToken and saved and saved.tooltipShowGuildRank then
            local guildName, guildRankName = GetGuildInfo(unitToken)
            if
                guildName
                and guildRankName
                and not (_isSecret and (_isSecret(guildName) or _isSecret(guildRankName)))
            then
                local suffix = " [" .. guildRankName .. "]"
                for i = 2, nLinesBefore do
                    local line = _G["GameTooltipTextLeft" .. i]
                    local textValue = line and line:GetText()
                    if
                        textValue
                        and not (_isSecret and _isSecret(textValue))
                        and string.find(textValue, guildName, 1, true)
                    then
                        if textValue:sub(-#suffix) ~= suffix then
                            line:SetText(textValue .. suffix)
                        end
                        break
                    end
                end
            end
        end
        -- M+ Score (append-only, deduped against an equivalent foreign line).
        if
            unitToken
            and saved
            and saved.tooltipMythicScore ~= false
            and C_PlayerInfo
            and C_PlayerInfo.GetPlayerMythicPlusRatingSummary
        then
            local details = C_PlayerInfo.GetPlayerMythicPlusRatingSummary(unitToken)
            local score = details and details.currentSeasonScore
            if
                score
                and not (_isSecret and _isSecret(score))
                and score > 0
                and not _tipHasLine(tip, CludesUI.L("M+ Score:"))
            then
                local sColor = C_ChallengeMode
                    and C_ChallengeMode.GetDungeonScoreRarityColor
                    and C_ChallengeMode.GetDungeonScoreRarityColor(score)
                local red, green, blue = 1, 1, 1
                if sColor then
                    red, green, blue = sColor.r, sColor.g, sColor.b
                end
                tip:AddDoubleLine(CludesUI.L("M+ Score:"), score, 1, 1, 1, red, green, blue)
            end
        end
        -- Mount name from the live helpful aura MountJournal recognizes. Opt-in (default off); per-GUID cached so refresh ticks on an unmounted player never re-walk the aura list.
        if
            unitToken
            and unitGuid
            and saved
            and saved.tooltipShowMount
            and not _tipHasLine(tip, CludesUI.L("Mount:"))
        then
            local mountLabel, mountCollected
            local cachedValue = _mountCache[unitGuid]
            local nowTime = GetTime()
            if cachedValue and (nowTime - cachedValue.time) < _mountCacheTTL then
                mountLabel = cachedValue.name
                mountCollected = cachedValue.collected
            else
                local nm, colour = _getMountedAuraName(unitToken)
                mountLabel = nm or false
                mountCollected = colour
                -- Expired entries are dropped, so only the last few seconds of hovers stay
                -- cached and this loop stays tiny; this player's stale entry is refreshed
                -- in place rather than replaced.
                for g, entry in pairs(_mountCache) do
                    if entry ~= cachedValue and (nowTime - entry.time) >= _mountCacheTTL then
                        _mountCache[g] = nil
                    end
                end
                if cachedValue then
                    cachedValue.name, cachedValue.collected, cachedValue.time =
                        mountLabel, mountCollected, nowTime
                else
                    _mountCache[unitGuid] = { name = mountLabel, collected = mountCollected, time = nowTime }
                end
            end
            if mountLabel then
                -- Green check / red X for whether YOU own this mount (nil = unknown, no marker).
                local valText = mountLabel
                if mountCollected == true then
                    valText = mountLabel .. " |TInterface\\RaidFrame\\ReadyCheck-Ready:0|t"
                elseif mountCollected == false then
                    valText = mountLabel .. " |TInterface\\RaidFrame\\ReadyCheck-NotReady:0|t"
                end
                tip:AddDoubleLine(CludesUI.L("Mount:"), valText, 1, 1, 1, 1, 1, 1)
            end
        end
        _ttShowBuffs(unitGuid, unitToken)
        -- Who the hovered player currently targets (opt-in, default off).
        _ttTargetLine(tip, unitToken)
        -- Item Level. Cache keyed strictly by the authoritative GUID so reads/writes can never land under a different person.
        if saved and saved.tooltipItemLevel ~= false then
            -- Re-activates after a mid-session toggle back on (login activation is in _ttInitData).
            if not _insp.active then
                _insp.Activate()
            end
            local ilvl
            if unitToken and UnitIsUnit(unitToken, "player") then
                local _, isEquipped = GetAverageItemLevel()
                if isEquipped and isEquipped > 0 then
                    ilvl = math.floor(isEquipped)
                end
            else
                local cachedValue = _ilvlCache[unitGuid]
                if cachedValue and (GetTime() - cachedValue.time) < _ilvlCacheTTL then
                    ilvl = cachedValue.ilvl
                elseif unitToken then
                    if C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
                        local value = C_PaperDollInfo.GetInspectItemLevel(unitToken)
                        if value and not (_isSecret and _isSecret(value)) and value > 0 then
                            ilvl = math.floor(value)
                            _ilvlCache[unitGuid] = { ilvl = ilvl, time = GetTime() }
                        end
                    end
                    local inspOpen = InspectFrame and InspectFrame:IsShown()
                    if not ilvl and not inspOpen and CanInspect(unitToken) and not InCombatLockdown() then
                        -- Paced and re-checked there; timed gaps are waited out, not dropped.
                        _requestTooltipInspect(unitGuid)
                    end
                end
            end
            if ilvl and not _tipHasLine(tip, CludesUI.L("Item Level")) then
                tip:AddDoubleLine(CludesUI.L("Item Level:"), ilvl, 1, 1, 1, 1, 1, 1)
                ttd.ilvlShown = true
            end
        end
        -- Re-apply our font to lines added after OnShow.
        _ttFonts(tip, nLinesBefore)
    end

    -- Visual reskin: dark bg/border (via _ttHook -> _ttSkin), CUI fonts, and restyled status bar. Gated on "Reskin Tooltip" (customTooltips).
    local function _ttInitVisual()
        for _, tip in ipairs({
            _GameTooltip,
            ShoppingTooltip1,
            ShoppingTooltip2,
            ItemRefTooltip,
            ItemRefShoppingTooltip1,
            ItemRefShoppingTooltip2,
            FriendsTooltip,
            EmbeddedItemTooltip,
            GameSmallHeaderTooltip,
            QuickKeybindTooltip,
            _G.WarCampaignTooltip,
            _G.ReputationParagonTooltip,
            _G.LibDBIconTooltip,
            _G.SettingsTooltip,
            QuestScrollFrame and QuestScrollFrame.StoryTooltip,
            QuestScrollFrame and QuestScrollFrame.CampaignTooltip,
        }) do
            _ttHook(tip)
        end
        if SharedTooltip_SetBackdropStyle then
            -- Deferred: SharedTooltip_SetBackdropStyle can fire from secure Blizzard code
            -- (casting bar, combat UI); a synchronous _ttSkin in the hook would taint the call stack (BackdropTemplate OnLoad propagates to CastingBarFrame).
            hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tip)
                C_Timer.After(0, function()
                    _ttSkin(tip)
                end)
            end)
        end
        if GameTooltipStatusBar then
            local sbBg = GameTooltipStatusBar:CreateTexture(nil, "BACKGROUND")
            sbBg:SetAllPoints()
            sbBg:SetColorTexture(0, 0, 0, 0.5)
            GameTooltipStatusBar:ClearAllPoints()
            GameTooltipStatusBar:SetPoint("BOTTOMLEFT", _GameTooltip, "BOTTOMLEFT", 1, 1)
            GameTooltipStatusBar:SetPoint("BOTTOMRIGHT", _GameTooltip, "BOTTOMRIGHT", -1, 1)
            -- Texture + height (the Show Health Strip cog); unset keeps UI-StatusBar at 3px.
            CludesUI._applyTooltipHealthStripStyle(true)
        end
    end

    -- Tooltip DATA additions: class-colored names, player-title control, M+ score,
    -- item level (via _ttUnitColor) and accent spell/macro titles. Each has its own
    -- toggle (tooltipPlayerTitles/tooltipMythicScore/tooltipItemLevel/accentReskinElements),
    -- gated by the customTooltips master (PLAYER_LOGIN calls this only when _enabled()),
    -- so disabling the reskin stops every tooltip option too. Idempotent: safe for the live re-apply path to call again.
    local _ttDataInited = false
    local function _ttInitData()
        if _ttDataInited then
            return
        end
        _ttDataInited = true
        -- Clear the recorded identity on hide so a late inspect result can never append to a closed/switched tooltip. HookScript (never SetScript) keeps the secure OnHide handler intact.
        _GameTooltip:HookScript("OnHide", function()
            _tipShownGUID = nil
        end)
        -- Item level inspect pacing starts at login, so the request history from other
        -- addons is already being tracked before the first hover.
        if not CludesUIDB or CludesUIDB.tooltipItemLevel ~= false then
            _insp.Activate()
        end
        -- Accent-color the title line for spells/macros (not items or units)
        local function _ttAccentTitle(tip)
            if tip ~= _GameTooltip or tip:IsForbidden() or not _accentEnabled() then
                return
            end
            if not _nameL1 then
                _nameL1 = _G.GameTooltipTextLeft1
            end
            if _nameL1 then
                local red, green, blue = _getElementColor()
                _nameL1:SetTextColor(red, green, blue)
            end
        end
        if
            TooltipDataProcessor
            and TooltipDataProcessor.AddTooltipPostCall
            and Enum
            and Enum.TooltipDataType
        then
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, _ttUnitColor)
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, _ttAccentTitle)
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Macro, _ttAccentTitle)
        else
            _GameTooltip:HookScript("OnTooltipSetUnit", _ttUnitColor)
            _GameTooltip:HookScript("OnTooltipSetSpell", _ttAccentTitle)
        end
    end

    -- Back-compat full init (data + visual), used by the live re-apply path.
    local function _ttInit()
        _ttInitData()
        _ttInitVisual()
    end

    -- Context menu skinning. Deliberately NOT memoised per frame: menu frames are
    -- pooled, so Blizzard hands the same frame back for the next menu and rebuilds
    -- its textures from the new description, silently undoing our background --
    -- an "already skinned" flag would skip reuse and leave Blizzard's background
    -- under our border. _menuSkinFrame is idempotent (skips owned regions,
    -- re-anchors relative to the frame, nothing accumulates), so running every pass self-heals reuse.

    local function _menuSkinFrame(widget)
        if not widget or widget:IsForbidden() or not _pmEnabled() then
            return
        end
        for i = 1, _select("#", widget:GetRegions()) do
            local regionFrame = _select(i, widget:GetRegions())
            if regionFrame and regionFrame:IsObjectType("Texture") and not GetFFD(regionFrame).owned then
                local RS = CludesUI.RESKIN
                regionFrame:SetColorTexture(RS.BG_R, RS.BG_G, RS.BG_B, 1)
                regionFrame:SetAlpha(RS.CTX_ALPHA)
                regionFrame:ClearAllPoints()
                regionFrame:SetPoint("TOPLEFT", widget, "TOPLEFT", 1, -1)
                regionFrame:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -1, 1)
            end
        end
        _applyConfiguredBorder(widget, "popupMenu", 1)
    end

    local function _menuOnOpen(manager, _, menuDescription)
        if not _pmEnabled() then
            return
        end
        -- Defer out of the secure context: this post-hook runs inside Blizzard's
        -- protected menu pipeline, so touching Blizzard objects here taints action bar buttons.
        --
        -- NEVER use menuDescription:AddMenuAcquiredCallback(): deferring the REGISTRATION
        -- doesn't help -- it plants an insecure Lua function that Blizzard itself CALLS
        -- from its pipeline, tainting the pipeline that builds the menu AND owns entry
        -- click handlers. Observed failure: right-click Whisper opened the chat edit box
        -- with a SECRET target name; the tainted ChatFrameUtil.OpenChat write made
        -- Blizzard's own ChatFrameEditBoxMixin:OnUpdate refuse SetText every frame (the terminating setText=0 never ran).
        --
        -- Self-owned staggered passes instead: fetch the menu frame from the manager and
        -- skin it ourselves, handing Blizzard nothing. Extra passes cover submenus and pooled frames acquired shortly after open.
        local function skinOpenMenu()
            local dropMenu = manager.GetOpenMenu and manager:GetOpenMenu()
            if dropMenu then
                _menuSkinFrame(dropMenu)
            end
        end
        C_Timer.After(0, skinOpenMenu)
        C_Timer.After(0.05, skinOpenMenu)
        C_Timer.After(0.15, skinOpenMenu)
    end

    -- Submenu coverage via the style mixin. The manager hooks above only ever
    -- see the ROOT menu: GetOpenMenu returns the root even during a flyout, a
    -- submenu frame is a parentless SIBLING of the root, and hovering a submenu
    -- parent fires neither OpenMenu nor OpenContextMenu. Blizzard instead styles
    -- every menu level through one code path (Menu.lua, MenuManagerMixin:AcquireMenu ->
    -- SecureGenerate: Mixin(proxy, menuDescription:GetMenuMixin()); proxy:Generate()).
    -- GetMenuMixin() resolves to the GLOBAL MenuStyle1Mixin (MenuStyle2Mixin for
    -- WowStyle2), and the Mixin() copy happens at every open, so a hooksecurefunc
    -- on the mixin's Generate is copied onto each menu frame and hands us that
    -- exact frame as self -- root and every flyout, no frame ID needed.
    --
    -- NOT the AddMenuAcquiredCallback mistake: that callback is an insecure closure
    -- invoked BARE (Menu.lua 2354, no securecallfunction) in the same execution that
    -- builds entry click handlers. Here containment is double: hooksecurefunc's contract keeps
    -- hook taint from propagating into the calling execution (so the Mixin() copy
    -- stays secure), and Blizzard wraps this call site in securecallfunction because
    -- addon-supplied menu mixins are an anticipated input (see MenuUtil.lua's
    -- GetDefaultContextMenuMixin override). NEVER ASSIGN into the mixin table
    -- (plants a tainted function) -- hooksecurefunc only.
    --
    -- The hook only collects and schedules; skinning runs from our own timer after
    -- the secure execution finishes. While a menu is open the compositor replaces
    -- the frame's metatable and disallows CreateTexture/CreateFontString/CreateLine,
    -- so only the EXISTING background region may be recoloured -- already how _menuSkinFrame operates.
    local _stylePending, _styleArmed = {}, false
    local function _styleFlush()
        _styleArmed = false
        for i = #_stylePending, 1, -1 do
            local frame = _stylePending[i]
            _stylePending[i] = nil
            -- _menuSkinFrame re-checks IsForbidden and the enable toggle.
            _menuSkinFrame(frame)
        end
    end
    local function _onStyleGenerate(menuFrame)
        _stylePending[#_stylePending + 1] = menuFrame
        if not _styleArmed then
            _styleArmed = true
            C_Timer.After(0, _styleFlush)
        end
    end

    local function _menuInit()
        if not _G.Menu or not _G.Menu.GetManager then
            return
        end
        local mgr = _G.Menu.GetManager()
        if not mgr then
            return
        end
        hooksecurefunc(mgr, "OpenMenu", function(self, ownerRegion, menuDescription)
            _menuOnOpen(self, ownerRegion, menuDescription)
        end)
        hooksecurefunc(mgr, "OpenContextMenu", function(self, ownerRegion, menuDescription)
            _menuOnOpen(self, ownerRegion, menuDescription)
        end)
        if _G.MenuStyle1Mixin and type(_G.MenuStyle1Mixin.Generate) == "function" then
            hooksecurefunc(_G.MenuStyle1Mixin, "Generate", _onStyleGenerate)
        end
        if _G.MenuStyle2Mixin and type(_G.MenuStyle2Mixin.Generate) == "function" then
            hooksecurefunc(_G.MenuStyle2Mixin, "Generate", _onStyleGenerate)
        end
    end

    local function _popupSkin(dialogFrame)
        if not dialogFrame or dialogFrame:IsForbidden() then
            return
        end
        if not _pmEnabled() then
            return
        end
        for i = 1, _select("#", dialogFrame:GetRegions()) do
            local region = _select(i, dialogFrame:GetRegions())
            if region and region:IsObjectType("Texture") and not GetFFD(region).owned then
                region:SetTexture(nil)
                if region.SetAtlas then
                    region:SetAtlas("")
                end
            end
        end
        if dialogFrame.BG then
            dialogFrame.BG:SetAlpha(0)
        end
        if dialogFrame.NineSlice then
            dialogFrame.NineSlice:SetAlpha(0)
        end
        if not GetFFD(dialogFrame).bg then
            local RS = CludesUI.RESKIN
            GetFFD(dialogFrame).bg = dialogFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
            GetFFD(dialogFrame).bg:SetAllPoints()
            GetFFD(dialogFrame).bg:SetColorTexture(RS.BG_R, RS.BG_G, RS.BG_B, RS.QT_ALPHA)
            GetFFD(GetFFD(dialogFrame).bg).owned = true
            if not _PP then
                _PP = CludesUI and CludesUI.PP
            end
            if _PP and _PP.CreateBorder then
                _PP.CreateBorder(dialogFrame, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
            end
        end
        GetFFD(dialogFrame).bg:Show()
        _applyConfiguredBorder(dialogFrame, "popupMenu", 1)
        local popupBtns = {}
        for i = 1, 4 do
            popupBtns[#popupBtns + 1] = dialogFrame["button" .. i]
                or _G[dialogFrame:GetName() and (dialogFrame:GetName() .. "Button" .. i)]
        end
        local popupName = dialogFrame.GetName and dialogFrame:GetName()
        popupBtns[#popupBtns + 1] = dialogFrame.extraButton or (popupName and _G[popupName .. "ExtraButton"])
        for _, button in ipairs(popupBtns) do
            if button and not GetFFD(button).skinned then
                GetFFD(button).skinned = true
                local regionList = { button:GetRegions() }
                for jdx = 1, #regionList do
                    local region = regionList[jdx]
                    if region and region:IsObjectType("Texture") and region ~= button:GetFontString() then
                        region:SetTexture(nil)
                        if region.SetAtlas then
                            region:SetAtlas("")
                        end
                    end
                end
                local btnBg = button:CreateTexture(nil, "BACKGROUND", nil, -6)
                btnBg:SetAllPoints()
                GetFFD(btnBg).owned = true
                GetFFD(button).bg = btnBg
                -- 10% white wash; the HIGHLIGHT layer only renders while the button is enabled and hovered.
                local hoverTex = button:CreateTexture(nil, "HIGHLIGHT")
                hoverTex:SetColorTexture(1, 1, 1, 0.1)
                hoverTex:SetAllPoints()
                GetFFD(hoverTex).owned = true

                -- Mirror Blizzard's enabled/disabled state so buttons visibly dim when locked out (e.g. Release in boss combat).
                local function _cuiRefreshEnabled(self)
                    local fontStr = self:GetFontString()
                    local enabled = (self.IsEnabled and self:IsEnabled()) and true or false
                    if fontStr then
                        if enabled then
                            -- Native mode enabled color is white.
                            if _elementColorMode() == "native" then
                                fontStr:SetTextColor(1, 1, 1, 1)
                            else
                                local red, green, blue = _getElementColor()
                                fontStr:SetTextColor(red, green, blue, 1)
                            end
                        else
                            fontStr:SetTextColor(0.4, 0.4, 0.4, 1)
                        end
                    end
                    if GetFFD(self).bg then
                        GetFFD(self).bg:SetAlpha(enabled and 1 or 0.5)
                    end
                end
                GetFFD(button).refreshEnabled = _cuiRefreshEnabled
                button:HookScript("OnEnable", _cuiRefreshEnabled)
                button:HookScript("OnDisable", _cuiRefreshEnabled)
                _cuiRefreshEnabled(button)
            end
            if button then
                local color = CludesUIDB and CludesUIDB.popupMenuButtonBackgroundColor
                    or { r = 0.1, g = 0.1, b = 0.1, a = 0.8 }
                if GetFFD(button).bg then
                    GetFFD(button).bg:SetColorTexture(color.r, color.g, color.b, color.a == nil and 0.8 or color.a)
                end
                _applyConfiguredBorder(button, "popupMenuButton", 1)
            end
        end

        -- Hook UpdateRecapButton once per popup to keep our per-button enabled visual in sync with Blizzard's enable/disable swaps.
        if dialogFrame.UpdateRecapButton and not GetFFD(dialogFrame).recapHooked then
            GetFFD(dialogFrame).recapHooked = true
            hooksecurefunc(dialogFrame, "UpdateRecapButton", function(self)
                for i = 1, 4 do
                    local b = self["button" .. i]
                    local func = b and GetFFD(b).refreshEnabled
                    if func then
                        func(b)
                    end
                end
            end)
        end

        -- Re-sync state for popups shown already-disabled
        for i = 1, 4 do
            local b = dialogFrame["button" .. i]
            local func = b and GetFFD(b).refreshEnabled
            if func then
                func(b)
            end
        end
        local editField = dialogFrame.editBox
            or (dialogFrame.GetName and _G[dialogFrame:GetName() .. "EditBox"])
        if editField and not GetFFD(editField).skinned then
            GetFFD(editField).skinned = true
            local regionList = { editField:GetRegions() }
            for jdx = 1, #regionList do
                local region = regionList[jdx]
                if region and region:IsObjectType("Texture") then
                    region:SetTexture(nil)
                    if region.SetAtlas then
                        region:SetAtlas("")
                    end
                end
            end
            -- Midnight edit boxes carry their art on a NineSlice child.
            if editField.NineSlice and editField.NineSlice.SetAlpha then
                editField.NineSlice:SetAlpha(0)
            end
            -- 6px left padding: box edge extends, text stays put.
            if CludesUI._WSkinPadInput then
                CludesUI._WSkinPadInput(editField)
            end
            local ebBg = editField:CreateTexture(nil, "BACKGROUND", nil, -6)
            ebBg:SetAllPoints()
            ebBg:SetColorTexture(0.05, 0.05, 0.05, 0.9)
            GetFFD(ebBg).owned = true
            -- Border matching the popup buttons: accent, or white in native.
            local borderR, borderG, borderB = 1, 1, 1
            if _elementColorMode() ~= "native" then
                borderR, borderG, borderB = _getElementColor()
            end
            if not _PP then
                _PP = CludesUI and CludesUI.PP
            end
            if _PP and _PP.CreateBorder then
                _PP.CreateBorder(editField, borderR, borderG, borderB, 0.5, 1, "OVERLAY", 7)
            end
        end
    end

    local function _popupInit()
        for i = 1, STATICPOPUP_NUMDIALOGS or 4 do
            local dialogFrame = _G["StaticPopup" .. i]
            if dialogFrame then
                dialogFrame:HookScript("OnShow", function(self)
                    _popupSkin(self)
                end)
            end
        end
    end

    ---------------------------------------------------------------------------
    --  Resurrect Accept Glow (resurrectAcceptGlow, default OFF)
    --  Pulsating border around button1 of the RESURRECT StaticPopups. Runs only
    --  while reskinPopupsMenus is on too (its options row greys out under it).
    --  Zero cost until first enable: no hooks or frames exist before then. The
    --  overlay is our own frame (state in FFD); the pulse is a C-side Alpha AnimationGroup, so no per-frame Lua.
    ---------------------------------------------------------------------------
    local RES_WHICH = {
        RESURRECT = true,
        RESURRECT_NO_SICKNESS = true,
        RESURRECT_NO_TIMER = true,
    }
    local _resGlowHooked = false

    local function _resGlowEnabled()
        local saved = CludesUIDB
        return saved and saved.resurrectAcceptGlow and saved.reskinPopupsMenus ~= false or false
    end

    local function _resGlowButton(dialogFrame)
        return dialogFrame.button1
            or (dialogFrame.GetName and dialogFrame:GetName() and _G[dialogFrame:GetName() .. "Button1"])
    end

    -- Addon-owned overlay 3px outside the button, built once per button on first glow; state lives in FFD, never on the Blizzard frame.
    local function _resGlowGet(button)
        local skinData = GetFFD(button)
        if not skinData.resGlow then
            local shade = CreateFrame("Frame", nil, button)
            shade:SetPoint("TOPLEFT", button, "TOPLEFT", -3, 3)
            shade:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 3, -3)
            shade:SetFrameLevel(button:GetFrameLevel() + 5)
            shade:Hide()
            if not _PP then
                _PP = CludesUI and CludesUI.PP
            end
            if _PP and _PP.CreateBorder then
                _PP.CreateBorder(shade, 1, 1, 1, 1, 2, "OVERLAY", 7)
            end
            local ag = shade:CreateAnimationGroup()
            ag:SetLooping("BOUNCE")
            local pulse = ag:CreateAnimation("Alpha")
            pulse:SetFromAlpha(1)
            pulse:SetToAlpha(0.15)
            pulse:SetDuration(0.7)
            pulse:SetSmoothing("IN_OUT")
            skinData.resGlow = shade
            skinData.resGlowAG = ag
        end
        return skinData.resGlow, skinData.resGlowAG
    end

    local function _resGlowStart(button)
        local shade, ag = _resGlowGet(button)
        if not shade then
            return
        end
        -- Color resolved every start so re-shows follow the current element color setting (same source as the popup skin).
        local ACC = CludesUI.CLUDES_GREEN
        if _PP and _PP.SetBorderColor then
            if _accentEnabled() and ACC then
                _PP.SetBorderColor(shade, ACC.r, ACC.g, ACC.b, 1)
            else
                _PP.SetBorderColor(shade, 1, 1, 1, 1)
            end
        end
        shade:SetAlpha(1)
        shade:Show()
        if ag and not ag:IsPlaying() then
            ag:Play()
        end
    end

    -- Raw FFD read (not GetFFD): stopping must never allocate state for a button that never glowed.
    local function _resGlowStop(button)
        local skinData = button and FFD[button]
        local shade = skinData and skinData.resGlow
        if shade then
            if skinData.resGlowAG then
                skinData.resGlowAG:Stop()
            end
            shade:Hide()
        end
    end

    local function _resGlowRefresh(dialogFrame)
        local button = _resGlowButton(dialogFrame)
        if not button then
            return
        end
        if _resGlowEnabled() and RES_WHICH[dialogFrame.which] and dialogFrame:IsShown() then
            _resGlowStart(button)
        else
            _resGlowStop(button)
        end
    end

    local function _resGlowRefreshAll()
        for i = 1, STATICPOPUP_NUMDIALOGS or 4 do
            local dialogFrame = _G["StaticPopup" .. i]
            if dialogFrame and not dialogFrame:IsForbidden() then
                _resGlowRefresh(dialogFrame)
            end
        end
    end

    -- Install OnShow/OnHide hooks once. Hooks cannot be uninstalled, so they self-gate (OnShow early-returns when off, OnHide is a raw weak-table lookup); never called before the first enable.
    local function _resGlowInit()
        if _resGlowHooked then
            return
        end
        _resGlowHooked = true
        for i = 1, STATICPOPUP_NUMDIALOGS or 4 do
            local dialogFrame = _G["StaticPopup" .. i]
            if dialogFrame then
                dialogFrame:HookScript("OnShow", function(self)
                    if not _resGlowEnabled() then
                        return
                    end
                    _resGlowRefresh(self)
                end)
                dialogFrame:HookScript("OnHide", function(self)
                    _resGlowStop(_resGlowButton(self))
                end)
            end
        end
    end

    -- Options-panel entry point: installs hooks on first enable and syncs visible popups on any flip, so no reload is needed.
    CludesUI._EnsureResurrectGlow = function()
        if _resGlowEnabled() then
            _resGlowInit()
        end
        if _resGlowHooked then
            _resGlowRefreshAll()
        end
        if CludesUI._repaintPopupPreview then
            CludesUI._repaintPopupPreview()
        end
    end

    do
        local frame = CreateFrame("Frame")
        frame:RegisterEvent("PLAYER_LOGIN")
        frame:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            -- customTooltips is the master for ALL CUI tooltip handling (visual reskin
            -- AND data additions); off leaves tooltips alone, matching the grayed-out
            -- options. Context menu/static popup reskins (reskinPopupsMenus) and
            -- per-window reskins use their own keys, seeded from the old master once by the
            -- blizzskin_reskin_master_split_v1 migration at parent ADDON_LOADED.
            if _enabled() then
                _ttInitData()
                _ttInitVisual()
            end
            if CludesUI.SyncAuraTooltipSkin then
                CludesUI.SyncAuraTooltipSkin()
            end
            if _pmEnabled() then
                _menuInit()
                _popupInit()
            end
            -- Independent of both reskin masters. Default OFF; disabled users pay only this boolean check (no hooks, no frames).
            if _resGlowEnabled() then
                _resGlowInit()
            end
        end)
    end
    CludesUI._initTooltipSkins = function()
        _ttInit()
        _menuInit()
        _popupInit()
    end

    ---------------------------------------------------------------------------
    --  Options header sample (Blizzard Skins+ > Tooltips & Menus)
    --  A unit tooltip of our own, dressed by the live skin and font passes.
    --  Its lines follow the Tooltip Extras the way _ttUnitColor and
    --  _ttLineColors write them, from the player's own unit (never secret)
    --  plus a fixed M+ score and mount. Built the first time the page asks;
    --  no events, no OnUpdate.
    ---------------------------------------------------------------------------
    local _pv = {} -- tt, strip, parent, place
    local _PV_SCORE = 2850
    local _PV_MOUNT_SPELL = 458 -- Brown Horse

    local function _pvLine(tip, textValue, c)
        if c then
            tip:AddLine(textValue, c.r, c.g, c.b)
        else
            tip:AddLine(textValue, 1, 1, 1)
        end
    end

    local function _pvPaint()
        local tip, hostFrame = _pv.tt, _pv.parent
        if not tip then
            return
        end
        local saved = CludesUIDB or {}
        local on = _enabled()
        -- Extras exist only under the reskin, as on the live tooltip.
        local posX = on and saved or {}
        local L = CludesUI.L
        if _pv.place then
            _pv.place(tip)
        end
        -- SetOwner clears the lines and re-owns the tooltip after the header was hidden.
        tip:SetOwner(hostFrame, "ANCHOR_NONE")

        local _, classFile = UnitClass("player")
        local classColor = classFile and _RAID_CC and _RAID_CC[classFile]
        local label = UnitName("player") or ""
        local titleText = (not on or posX.tooltipPlayerTitles) and UnitPVPName("player")
        if titleText and _isSecret and _isSecret(titleText) then
            titleText = nil
        end
        local line1 = (titleText and titleText ~= "") and titleText or label
        if posX.tooltipAFKTag then
            line1 = line1 .. " " .. GRAY_FONT_COLOR:WrapTextInColorCode(CHAT_FLAG_AFK)
        end
        _pvLine(tip, line1, on and classColor or nil)

        -- Without a guild (or with a secret one) Blizzard's own words stand in, uncolored.
        local gName, gRank = GetGuildInfo("player")
        local inGuild = gName and not (_isSecret and (_isSecret(gName) or _isSecret(gRank)))
        if not inGuild then
            gName, gRank = GUILD, RANK
        end
        if posX.tooltipShowGuildRank then
            gName = gName .. " [" .. (gRank or RANK) .. "]"
        end
        _pvLine(tip, gName, inGuild and posX.tooltipGuildmateColor and ChatTypeInfo.GUILD or nil)

        -- Level line as _ttLineColors leaves it: compact, or the number colored by difficulty.
        local lvl, race = UnitEffectiveLevel("player"), UnitRace("player") or ""
        if _isSecret and _isSecret(lvl) then
            lvl = 0
        end
        local red, green, blue
        if posX.tooltipLevelColor and CludesUI.GetLevelColor then
            red, green, blue = CludesUI.GetLevelColor("player", lvl, true)
        end
        if posX.tooltipCompactLevel then
            _pvLine(tip, CludesUI.ColorText(lvl, red, green, blue) .. " " .. race)
        else
            local textValue = UNIT_TYPE_LEVEL_TEMPLATE:format(lvl, race)
            if red then
                textValue = textValue:gsub("%d+", CludesUI.ColorText("%0", red, green, blue), 1)
            end
            _pvLine(tip, textValue)
        end

        local className = UnitClass("player") or ""
        local specInfo
        local position = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()
        if position then
            specInfo = select(2, C_SpecializationInfo.GetSpecializationInfo(position))
        end
        _pvLine(
            tip,
            specInfo and (specInfo .. " " .. className) or className,
            posX.tooltipClassLineColor and classColor or nil
        )

        local _, faction = UnitFactionGroup("player")
        if faction then
            _pvLine(tip, faction, posX.tooltipFactionColor and _FACTION_CC[faction] or nil)
        end

        -- No Mythic+ on WoW Forever: the live line never shows there (no score above 0).
        if
            on
            and saved.tooltipMythicScore ~= false
            and not CludesUI.IS_FOREVER
            and C_PlayerInfo
            and C_PlayerInfo.GetPlayerMythicPlusRatingSummary
        then
            local sc = C_ChallengeMode
                and C_ChallengeMode.GetDungeonScoreRarityColor
                and C_ChallengeMode.GetDungeonScoreRarityColor(_PV_SCORE)
            tip:AddDoubleLine(
                L("M+ Score:"),
                _PV_SCORE,
                1,
                1,
                1,
                sc and sc.r or 1,
                sc and sc.g or 1,
                sc and sc.b or 1
            )
        end
        local mount = posX.tooltipShowMount and C_Spell.GetSpellName(_PV_MOUNT_SPELL)
        if mount then
            tip:AddDoubleLine(
                L("Mount:"),
                mount .. " |TInterface\\RaidFrame\\ReadyCheck-Ready:0|t",
                1,
                1,
                1,
                1,
                1,
                1
            )
        end
        if posX.tooltipShowTarget then
            tip:AddDoubleLine(L("Targeting:"), L("You"), 1, 1, 1, 0.1, 1, 0.1)
        end
        if on and saved.tooltipItemLevel ~= false then
            local _, isEquipped = GetAverageItemLevel()
            if isEquipped and isEquipped > 0 then
                tip:AddDoubleLine(L("Item Level:"), math.floor(isEquipped), 1, 1, 1, 1, 1, 1)
            end
        end

        -- The look: the live skin and fonts, or Blizzard's own frame and fonts
        -- with the reskin off (a switch that waits for its reload).
        local payload = GetFFD(tip)
        if on then
            if payload.bg then
                payload.bg:Show()
            end
            if payload.configBorder then
                payload.configBorder:Show()
            end
            _ttSkin(tip)
            _ttFonts(tip)
        else
            if tip.NineSlice then
                tip.NineSlice:SetAlpha(1)
            end
            if payload.bg then
                payload.bg:Hide()
            end
            if payload.configBorder then
                payload.configBorder:Hide()
            end
            local nm = tip:GetName()
            for i = 1, tip:NumLines() do
                local leftX, right = _G[nm .. "TextLeft" .. i], _G[nm .. "TextRight" .. i]
                if leftX then
                    leftX:SetFontObject(i == 1 and GameTooltipHeaderText or GameTooltipText)
                end
                if right then
                    right:SetFontObject(GameTooltipText)
                end
            end
        end
        tip:Show()

        -- Health strip: inside the bottom edge under the reskin, styled by the
        -- live strip's own pass; Blizzard's bar below the tooltip without it.
        local topStrip = _pv.strip
        local below = 0
        if saved.tooltipHideHealthStrip == false then
            if not topStrip then
                topStrip = CreateFrame("StatusBar", nil, tip)
                topStrip:SetMinMaxValues(0, 1)
                topStrip.bg = topStrip:CreateTexture(nil, "BACKGROUND")
                topStrip.bg:SetAllPoints()
                topStrip.bg:SetColorTexture(0, 0, 0, 0.5)
                _pv.strip = topStrip
            end
            topStrip:SetValue(1)
            topStrip:ClearAllPoints()
            if on then
                topStrip:SetPoint("BOTTOMLEFT", tip, "BOTTOMLEFT", 1, 1)
                topStrip:SetPoint("BOTTOMRIGHT", tip, "BOTTOMRIGHT", -1, 1)
                topStrip:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
                topStrip:SetHeight(3)
                topStrip.bg:Show()
                if CludesUI._applyTooltipHealthStripStyle then
                    CludesUI._applyTooltipHealthStripStyle(nil, topStrip)
                end
            else
                topStrip:SetPoint("TOPLEFT", tip, "BOTTOMLEFT", 2, -1)
                topStrip:SetPoint("TOPRIGHT", tip, "BOTTOMRIGHT", -2, -1)
                topStrip:SetStatusBarTexture("Interface\\TargetingFrame\\UI-TargetingFrame-BarFill")
                topStrip:SetHeight(8)
                topStrip.bg:Hide()
                below = 9
            end
            local color = classColor or HIGHLIGHT_FONT_COLOR
            topStrip:SetStatusBarColor(color.r, color.g, color.b)
            topStrip:Show()
        elseif topStrip then
            topStrip:Hide()
        end
        if _pv.place then
            _pv.place(tip, tip:GetWidth(), tip:GetHeight() + below)
        end
    end

    -- A write on the Tooltips page: the shown sample paints again.
    CludesUI._repaintTooltipPreview = function()
        local p = _pv.tt and _pv.tt:GetParent()
        if p and p:IsVisible() then
            _pvPaint()
        end
    end

    -- Shows the sample under parent and paints it. place(tt) runs before the
    -- paint (scale it), place(tt, w, h) after it (anchor it, size the header).
    function CludesUI.ShowTooltipPreview(hostFrame, place)
        if not _pv.tt then
            _pv.tt = CreateFrame("GameTooltip", "CludesUITooltipPreview", hostFrame, "SharedTooltipTemplate")
            _pv.tt:SetClampedToScreen(false)
        end
        local tip = _pv.tt
        tip:SetParent(hostFrame)
        tip:SetFrameStrata(hostFrame:GetFrameStrata())
        tip:SetFrameLevel(hostFrame:GetFrameLevel() + 5)
        _pv.parent, _pv.place = hostFrame, place
        _pvPaint()
        return tip
    end

    -- Popup sample: Blizzard's resurrect dialog in its own words, dressed by
    -- _popupSkin and the resurrect glow like a live StaticPopup. Without the
    -- reskin since login it keeps Blizzard's dialog art; switched off later it
    -- dims, as the live popups wait for the reload.
    local _pp = {} -- f, place

    local function _ppButton(frame, textValue)
        local b = CreateFrame("Button", nil, frame)
        b:SetSize(128, 21)
        b:EnableMouse(false)
        b:SetNormalTexture("Interface\\Buttons\\UI-DialogBox-Button-Up")
        b:GetNormalTexture():SetTexCoord(0, 1, 0, 0.71875)
        b:SetNormalFontObject(GameFontNormal)
        b:SetText(textValue)
        return b
    end

    local function _ppPaint()
        local frame = _pp.f
        if not frame then
            return
        end
        if _pp.place then
            _pp.place(frame)
        end
        local on = _pmEnabled()
        frame:Show()
        if on then
            _popupSkin(frame)
        end
        _resGlowRefresh(frame)
        frame:SetAlpha((on or not GetFFD(frame).bg) and 1 or 0.3)
        if _pp.place then
            _pp.place(frame, frame:GetWidth(), frame:GetHeight())
        end
    end

    CludesUI._repaintPopupPreview = function()
        local p = _pp.f and _pp.f:GetParent()
        if p and p:IsVisible() then
            _ppPaint()
        end
    end

    -- Same contract as ShowTooltipPreview. Named: _popupSkin builds child names from it.
    function CludesUI.ShowPopupPreview(hostFrame, place)
        local frame = _pp.f
        if not frame then
            frame = CreateFrame("Frame", "CludesUIPopupPreview", hostFrame)
            frame.which = "RESURRECT"
            local backdrop = frame:CreateTexture(nil, "BACKGROUND")
            backdrop:SetAtlas("UI-DialogBox-Background-Dark")
            backdrop:SetAllPoints()
            frame.text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            frame.text:SetWidth(290)
            frame.text:SetPoint("TOP", frame, "TOP", 0, -16)
            frame.text:SetText(RESURRECT_REQUEST:format(UnitName("player") or ""))
            frame.button1 = _ppButton(frame, ACCEPT)
            frame.button1:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -6, 16)
            frame.button2 = _ppButton(frame, DECLINE)
            frame.button2:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 6, 16)
            frame:SetSize(320, 16 + frame.text:GetStringHeight() + 16 + 21 + 16)
            _pp.f = frame
        end
        frame:SetParent(hostFrame)
        frame:SetFrameStrata(hostFrame:GetFrameStrata())
        frame:SetFrameLevel(hostFrame:GetFrameLevel() + 5)
        _pp.place = place
        _ppPaint()
        return frame
    end

    -- Mirror the tooltip skin onto the ENGINE aura tooltip (AuraButtonTooltip,
    -- the forbidden GameTooltip clone every aura container button uses -- addon
    -- hooks can never touch it directly). Build 68914 exposes global styling entry
    -- points for it: resolved DEFENSIVELY (public-env reachability is a field-verify
    -- item) and pcall'd throughout. Applied at login and from tooltip-skin setters; skin off restores the engine default style.
    function CludesUI.SyncAuraTooltipSkin()
        CludesUI._repaintTooltipPreview()
        local inb = _G.AuraContainerInbound
        if not inb then
            return
        end
        if _enabled() then
            if not inb.SetTooltipBackdrop then
                return
            end
            local cr, cg, cb, ca = CludesUI.GetTooltipBg()
            local _, _, _, _, legacySize = CludesUI.GetTooltipBorder()
            local saved, size, key, color, alpha = _resolveConfiguredBorder("tooltip", legacySize)
            local details = {
                backdropInfo = {
                    bgFile = "Interface\\Buttons\\WHITE8X8",
                    insets = { left = 0, right = 0, top = 0, bottom = 0 },
                },
                centerColor = CreateColor(cr or 0, cg or 0, cb or 0, ca or 0.9),
            }
            -- Same style, size and placement as the GameTooltip border (ApplyBorderStyle,
            -- through CludesUI.BorderPlacement), drawn by the one backdrop the engine
            -- allows; insets keep the fill on the tooltip.
            if size > 0 then
                local texture = saved.tooltipBorderTexture or "solid"
                local pixel = CludesUI.BorderPx(saved.tooltipBorderThicknessPx, size, texture)
                local edgeFile = CludesUI.ResolveBorderTexture(texture)
                local edge, ox, oy, sx, sy
                if edgeFile then
                    edge, ox, oy, sx, sy = CludesUI.BorderPlacement(
                        size,
                        texture,
                        saved.tooltipBorderOffsetX,
                        saved.tooltipBorderOffsetY,
                        saved.tooltipBorderShiftX,
                        saved.tooltipBorderShiftY,
                        "blizzardSkin",
                        key,
                        pixel
                    )
                else
                    -- Solid: the PP line, (px or size) whole pixels inside the tooltip.
                    edgeFile = "Interface\\Buttons\\WHITE8X8"
                    edge, ox, oy, sx, sy = (pixel or size) * CludesUI.PP.mult, 0, 0, 0, 0
                end
                details.backdropInfo.edgeFile = edgeFile
                details.backdropInfo.edgeSize = edge
                details.backdropInfo.insets =
                    { left = ox - sx, right = ox + sx, top = oy + sy, bottom = oy - sy }
                details.anchorOffsets = { left = sx - ox, right = sx + ox, top = sy + oy, bottom = sy - oy }
                details.borderColor = CreateColor(color.r, color.g, color.b, alpha)
            end
            pcall(inb.SetTooltipBackdrop, details)
        elseif inb.ResetTooltipStyle then
            pcall(inb.ResetTooltipStyle)
        end
    end

    ---------------------------------------------------------------------------
    --  LFG Queue Accept Popup: reskin + countdown timer bar
    --  Skins LFGDungeonReadyPopup the same way we skin StaticPopups, and
    --  adds an accent-colored countdown bar below the popup.
    ---------------------------------------------------------------------------
    do
        local TIMER_DURATION = 40
        local timerFill, timerLabel, timerEndTime

        -- Independent toggle, default on: this is a popup, not a window, so no master reskin setting (including window-skins style) governs it.
        local function IsQueueReskinOn()
            return not CludesUIDB or CludesUIDB.reskinQueuePopup ~= false
        end

        -- popup/dialog/closeBtn default to the LFG dungeon trio. The params
        -- exist so a caller can pass a different popup/dialog pair; PvP support
        -- was built on that and then SCRAPPED by maintainer call, so the LFG popup
        -- is currently the only caller and the defaults are always used.
        local function SkinQueuePopup(dialogFrame, dlg, closeButton)
            dialogFrame = dialogFrame or LFGDungeonReadyPopup
            if not dialogFrame then
                return
            end

            -- Strip Blizzard border/decoration on popup and dialog, preserving dialog.background (the dungeon art image).
            dlg = dlg or LFGDungeonReadyDialog
            local keepTextures = {}
            if dlg and dlg.background then
                keepTextures[dlg.background] = true
            end
            if dlg and dlg.bottomArt then
                keepTextures[dlg.bottomArt] = true
            end
            -- Kept, but KNOCKED BACK. The dungeon art is dim and atmospheric so
            -- it sat behind the skin fine; the arena/BG art is bright and busy
            -- and fought it. Dimming keeps every queue type consistent (they all
            -- still show their own art) while letting the dark skin dominate.
            -- Re-applied every show: Blizzard re-sets the texture per pop.
            for _, widget in ipairs({ dialogFrame, dlg }) do
                if widget then
                    for i = 1, _select("#", widget:GetRegions()) do
                        local region = _select(i, widget:GetRegions())
                        if
                            region
                            and region:IsObjectType("Texture")
                            and not GetFFD(region).owned
                            and not keepTextures[region]
                        then
                            region:SetTexture(nil)
                            if region.SetAtlas then
                                region:SetAtlas("")
                            end
                        end
                    end
                    if widget.BG then
                        widget.BG:SetAlpha(0)
                    end
                    if widget.NineSlice then
                        widget.NineSlice:SetAlpha(0)
                    end
                    if widget.Border then
                        widget.Border:SetAlpha(0)
                    end
                end
            end

            closeButton = closeButton or _G.LFGDungeonReadyDialogCloseButton
            if closeButton then
                for i = 1, _select("#", closeButton:GetRegions()) do
                    local region = _select(i, closeButton:GetRegions())
                    if region and region:IsObjectType("Texture") and not GetFFD(region).owned then
                        region:SetAlpha(0)
                    end
                end
                if not GetFFD(closeButton).icon then
                    local icoW, icoH = closeButton:GetSize()
                    local ico = closeButton:CreateTexture(nil, "OVERLAY", nil, 7)
                    ico:SetSize((icoW or 16) - 2, (icoH or 16) - 2)
                    ico:SetPoint("CENTER", closeButton, "CENTER", -4, 4)
                    ico:SetAtlas("UI-QuestTrackerButton-Secondary-Collapse-Pressed")
                    GetFFD(ico).owned = true
                    GetFFD(closeButton).icon = ico
                end
                GetFFD(closeButton).icon:Show()
            end

            -- Our dark background + border (create once), anchored to the dialog (not the popup wrapper) so the skin follows if a mover addon drags LFGDungeonReadyDialog independently.
            if not GetFFD(dialogFrame).bg then
                local RS = CludesUI.RESKIN
                if not _PP then
                    _PP = CludesUI and CludesUI.PP
                end
                local anchor = dlg or dialogFrame
                -- SIBLING, not a child. A child frame draws ABOVE its parent's
                -- own texture regions even at the same frame level, and
                -- genuinely went below it and this was invisible there.)
                --
                -- Parented to the dialog's own parent and one level down, it is
                -- a true sibling and draws underneath.
                local bgFrame = CreateFrame("Frame", nil, anchor)
                bgFrame:SetAllPoints(anchor)
                bgFrame:SetFrameLevel(math.max(1, anchor:GetFrameLevel() - 1))
                -- VISIBILITY MUST BE TIED MANUALLY. As a child of the dialog it
                -- inherited hide for free; as a SIBLING (which is what makes it
                -- draw below their art) it does not, so it survived the dialog
                -- closing and left a black box -- with the timer bar, which is
                -- parented to it, still ticking inside.
                GetFFD(dialogFrame).bgFrame = bgFrame
                GetFFD(dialogFrame).bg = bgFrame:CreateTexture(nil, "ARTWORK")
                GetFFD(dialogFrame).bg:SetAllPoints()
                GetFFD(dialogFrame).bg:SetColorTexture(RS.BG_R, RS.BG_G, RS.BG_B, RS.QT_ALPHA)
                GetFFD(GetFFD(dialogFrame).bg).owned = true
            end
            _applyConfiguredBorder(GetFFD(dialogFrame).bgFrame, "popupMenu", 1)

            -- Enter Dungeon / Leave Queue. Textures are re-stripped every show (Blizzard re-applies art per popup); bg/border created once.
            if dlg then
                for _, btnName in ipairs({ "enterButton", "leaveButton" }) do
                    local button = dlg[btnName]
                    if button then
                        -- Named Left/Middle/Right textures are swapped by C++ on mouse down, so SetTexture alone does not stick.
                        local regionList = { button:GetRegions() }
                        for jdx = 1, #regionList do
                            local region = regionList[jdx]
                            if
                                region
                                and region:IsObjectType("Texture")
                                and not GetFFD(region).owned
                                and region ~= button:GetFontString()
                            then
                                region:SetAlpha(0)
                            end
                        end
                        if button.Left then
                            button.Left:SetAlpha(0)
                        end
                        if button.Middle then
                            button.Middle:SetAlpha(0)
                        end
                        if button.Right then
                            button.Right:SetAlpha(0)
                        end
                        if not GetFFD(button).skinned then
                            GetFFD(button).skinned = true
                            -- Hook SetAlpha on the named textures so C++ press state changes cannot make them visible again.
                            for _, texKey in ipairs({ "Left", "Middle", "Right" }) do
                                local texture = button[texKey]
                                if texture and texture.SetAlpha then
                                    hooksecurefunc(texture, "SetAlpha", function(self, a)
                                        if a > 0 then
                                            self:SetAlpha(0)
                                        end
                                    end)
                                end
                            end
                            local ACC = CludesUI.CLUDES_GREEN
                            local useAccent = _accentEnabled() and ACC
                            local RS2 = CludesUI.RESKIN
                            local btnBg = button:CreateTexture(nil, "BACKGROUND", nil, -6)
                            btnBg:SetAllPoints()
                            GetFFD(btnBg).owned = true
                            GetFFD(button).bg = btnBg
                            -- 10% white wash; marked owned so the every-show re-strip above leaves it alone.
                            local hoverTex = button:CreateTexture(nil, "HIGHLIGHT")
                            hoverTex:SetColorTexture(1, 1, 1, 0.1)
                            hoverTex:SetAllPoints()
                            GetFFD(hoverTex).owned = true
                        end
                        -- Colors re-applied every show.
                        local color = CludesUIDB and CludesUIDB.popupMenuButtonBackgroundColor
                            or { r = 0.1, g = 0.1, b = 0.1, a = 0.8 }
                        if GetFFD(button).bg then
                            GetFFD(button).bg:SetColorTexture(color.r, color.g, color.b, color.a == nil and 0.8 or color.a)
                        end
                        _applyConfiguredBorder(button, "popupMenuButton", 1)
                        local fontStr = button:GetFontString()
                        if fontStr then
                            -- Native mode text is plain white.
                            if _elementColorMode() == "native" then
                                fontStr:SetTextColor(1, 1, 1, 1)
                            else
                                local red, green, blue = _getElementColor()
                                fontStr:SetTextColor(red, green, blue, 1)
                            end
                        end
                    end
                end
            end
        end

        local timerEdge, timerBg

        -- True once the user has touched ANY Queue Timer Style setting. Gates the
        -- unified style below off the Blizzard-style branch: reskin-off users chose
        -- the stock look, so an untouched profile keeps the legacy rendering
        -- byte-identically; the first setting they touch activates the unified
        -- style in both modes (and a section reset returns them to legacy).
        local function QueueTimerCustomized()
            local saved = CludesUIDB
            return (
                saved
                and (
                    saved.queueTimerTextColor ~= nil
                    or saved.queueTimerTextSize ~= nil
                    or saved.queueTimerBarHeight ~= nil
                    or saved.queueTimerTextOffsetY ~= nil
                )
            )
                    and true
                or false
        end

        -- Applied after either style branch, so the look holds with the reskin on or off.
        local function ApplyTimerStyle()
            if not timerFill then
                return
            end
            if GetFFD(timerFill).style == false and not QueueTimerCustomized() then
                -- Legacy stock rendering, exactly as before the style controls existed.
                timerLabel:SetFontObject("GameFontHighlight")
                timerLabel:ClearAllPoints()
                timerLabel:SetPoint("CENTER", timerFill, "CENTER", 0, 0)
                timerFill:SetHeight(9)
                return
            end
            local saved = CludesUIDB or {}
            local QT = CludesUI.QUEUE_TIMER
            local color = saved.queueTimerTextColor
            local fontFile = (CludesUI.GetFontPath("extras")) or "Fonts\\FRIZQT__.TTF"
            CludesUI.PrimeFontShadow(timerLabel, true)
            timerLabel:SetFont(fontFile, saved.queueTimerTextSize or QT.TEXT_SIZE, "")
            timerLabel:SetTextColor(
                (color and color.r) or QT.TEXT_R,
                (color and color.g) or QT.TEXT_G,
                (color and color.b) or QT.TEXT_B,
                1
            )
            timerLabel:ClearAllPoints()
            timerLabel:SetPoint(
                "CENTER",
                timerFill,
                "CENTER",
                0,
                saved.queueTimerTextOffsetY or QT.TEXT_OFFSET_Y
            )
            timerFill:SetHeight(saved.queueTimerBarHeight or QT.BAR_HEIGHT)
        end
        CludesUI.RefreshQueueTimerStyle = ApplyTimerStyle

        local function ShowQueueTimer(useEuiStyle)
            local dialogFrame = LFGDungeonReadyPopup
            if not dialogFrame then
                return
            end

            if not timerFill then
                local timerParent = GetFFD(dialogFrame).bgFrame or dialogFrame
                timerFill = CreateFrame("StatusBar", nil, timerParent)
                timerFill:SetMinMaxValues(0, TIMER_DURATION)

                timerBg = timerFill:CreateTexture(nil, "BACKGROUND")
                timerBg:SetAllPoints()
                timerBg:SetColorTexture(0, 0, 0, 0.7)

                -- Blizzard-style casting bar border (hidden in CUI style).
                timerEdge = timerFill:CreateTexture(nil, "OVERLAY")
                timerEdge:SetTexture(130874)
                timerEdge:SetSize(256, 64)
                timerEdge:SetPoint("TOP", timerFill, 0, 28)

                timerLabel = timerFill:CreateFontString(nil, "OVERLAY", "GameFontHighlight")

                CludesUI.RegAccent({
                    type = "callback",
                    fn = function()
                        if GetFFD(timerFill).style then
                            local red, green, b = CludesUI.GetAccentColor()
                            timerFill:SetStatusBarColor(red, green, b, 0.75)
                        end
                    end,
                })
            end

            -- Anchor to the dialog, not the popup wrapper, so the timer follows it when a mover addon drags the dialog independently.
            local dlg = LFGDungeonReadyDialog
            local anchorFrame = dlg or dialogFrame

            -- The bar's parent sits a level below the dialog so its backdrop draws under the dialog art; a raised countdown must not.
            timerFill:SetFrameLevel(anchorFrame:GetFrameLevel() + 5)

            timerFill:ClearAllPoints()
            if useEuiStyle then
                timerFill:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                local mult = (_PP and _PP.mult) or 1
                timerFill:SetPoint("BOTTOMLEFT", anchorFrame, "BOTTOMLEFT", mult, mult)
                timerFill:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", -mult, mult)
                local accR, accG, accB = CludesUI.GetAccentColor()
                timerFill:SetStatusBarColor(accR, accG, accB, 0.75)
                timerBg:SetColorTexture(0, 0, 0, 0.5)
                timerEdge:Hide()
                timerBg:Show()
                GetFFD(timerFill).style = true
            else
                -- Blizzard style: stock bar texture + casting-bar border art.
                timerFill:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
                timerFill:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -5)
                timerFill:SetWidth(190)
                timerFill:SetStatusBarColor(1, 0.1, 0)
                timerEdge:Show()
                timerBg:Show()
                GetFFD(timerFill).style = false
            end

            ApplyTimerStyle()

            -- Hide any other addon's timer bar parented to the popup.
            for _, childFrame in ipairs({ dialogFrame:GetChildren() }) do
                if
                    childFrame ~= timerFill
                    and childFrame.GetObjectType
                    and childFrame:GetObjectType() == "StatusBar"
                then
                    childFrame:Hide()
                end
            end

            timerEndTime = GetTime() + TIMER_DURATION
            timerFill:SetValue(TIMER_DURATION)
            timerLabel:SetText(format("%d", TIMER_DURATION))
            timerFill:Show()

            timerFill:SetScript("OnUpdate", function(self)
                local remaining = timerEndTime - GetTime()
                if remaining <= 0 then
                    self:SetScript("OnUpdate", nil)
                    self:Hide()
                    return
                end
                self:SetValue(remaining)
                timerLabel:SetText(format("%d", math.ceil(remaining)))
            end)
        end

        -- The "queue missed" / role check status popup.
        local function SkinQueueStatus()
            local statusText = _G.LFGDungeonReadyStatus
            if not statusText or not IsQueueReskinOn() then
                return
            end
            -- Textures re-stripped every show.
            for i = 1, _select("#", statusText:GetRegions()) do
                local region = _select(i, statusText:GetRegions())
                if region and region:IsObjectType("Texture") and not GetFFD(region).owned then
                    region:SetTexture(nil)
                    if region.SetAtlas then
                        region:SetAtlas("")
                    end
                end
            end
            if statusText.BG then
                statusText.BG:SetAlpha(0)
            end
            if statusText.NineSlice then
                statusText.NineSlice:SetAlpha(0)
            end
            if statusText.Border then
                statusText.Border:SetAlpha(0)
            end
            if not GetFFD(statusText).bg then
                local RS = CludesUI.RESKIN
                GetFFD(statusText).bg = statusText:CreateTexture(nil, "BACKGROUND", nil, -8)
                GetFFD(statusText).bg:SetAllPoints()
                GetFFD(statusText).bg:SetColorTexture(RS.BG_R, RS.BG_G, RS.BG_B, RS.QT_ALPHA)
                GetFFD(GetFFD(statusText).bg).owned = true
                if not _PP then
                    _PP = CludesUI and CludesUI.PP
                end
                if _PP and _PP.CreateBorder then
                    _PP.CreateBorder(statusText, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
                end
            end
        end

        -- Hook OnShow so the skin applies the moment the acceptance panel appears, before any specific event fires.
        local _statusHooked = false
        local function HookStatusOnShow()
            if _statusHooked then
                return
            end
            local statusText = _G.LFGDungeonReadyStatus
            if not statusText then
                return
            end
            _statusHooked = true
            statusText:HookScript("OnShow", function()
                SkinQueueStatus()
            end)
        end

        -- Accept/Decline both inherit stock UIPanelButtonTemplate and were never
        -- touched, same treatment as SkinQueuePopup's enterButton/leaveButton.
        local function SkinRoleCheckButton(button)
            if not button then
                return
            end
            local regionList = { button:GetRegions() }
            for jdx = 1, #regionList do
                local region = regionList[jdx]
                if
                    region
                    and region:IsObjectType("Texture")
                    and not GetFFD(region).owned
                    and region ~= button:GetFontString()
                then
                    region:SetAlpha(0)
                end
            end
            if button.Left then
                button.Left:SetAlpha(0)
            end
            if button.Middle then
                button.Middle:SetAlpha(0)
            end
            if button.Right then
                button.Right:SetAlpha(0)
            end
            if not GetFFD(button).skinned then
                GetFFD(button).skinned = true
                for _, texKey in ipairs({ "Left", "Middle", "Right" }) do
                    local texture = button[texKey]
                    if texture and texture.SetAlpha then
                        hooksecurefunc(texture, "SetAlpha", function(self, a)
                            if a > 0 then
                                self:SetAlpha(0)
                            end
                        end)
                    end
                end
                local btnBg = button:CreateTexture(nil, "BACKGROUND", nil, -6)
                btnBg:SetAllPoints()
                GetFFD(btnBg).owned = true
                GetFFD(button).bg = btnBg
                local hoverTex = button:CreateTexture(nil, "HIGHLIGHT")
                hoverTex:SetColorTexture(1, 1, 1, 0.1)
                hoverTex:SetAllPoints()
                GetFFD(hoverTex).owned = true
            end
            local color = CludesUIDB and CludesUIDB.popupMenuButtonBackgroundColor
                or { r = 0.1, g = 0.1, b = 0.1, a = 0.8 }
            if GetFFD(button).bg then
                GetFFD(button).bg:SetColorTexture(color.r, color.g, color.b, color.a == nil and 0.8 or color.a)
            end
            _applyConfiguredBorder(button, "popupMenuButton", 1)
            local fontStr = button:GetFontString()
            if fontStr then
                if _elementColorMode() == "native" then
                    fontStr:SetTextColor(1, 1, 1, 1)
                else
                    local red, green, blue = _getElementColor()
                    fontStr:SetTextColor(red, green, blue, 1)
                end
            end
        end

        -- The "Confirm your role" popup shown to the whole party when ANYONE queues
        -- (leader or otherwise) and roles aren't already locked in. LFG_PROPOSAL_SHOW
        -- only fires for the later group-found step, so this frame is hooked directly.
        -- Only the outer chrome is stripped; the role icons live on separate child
        -- buttons (RoleButtonTank/Healer/DPS), never direct regions of this frame.
        local function SkinRoleCheckPopup()
            local dialogFrame = _G.LFDRoleCheckPopup
            if not dialogFrame or not IsQueueReskinOn() then
                return
            end
            for i = 1, _select("#", dialogFrame:GetRegions()) do
                local region = _select(i, dialogFrame:GetRegions())
                if region and region:IsObjectType("Texture") and not GetFFD(region).owned then
                    region:SetTexture(nil)
                    if region.SetAtlas then
                        region:SetAtlas("")
                    end
                end
            end
            if dialogFrame.BG then
                dialogFrame.BG:SetAlpha(0)
            end
            if dialogFrame.NineSlice then
                dialogFrame.NineSlice:SetAlpha(0)
            end
            if dialogFrame.Border then
                dialogFrame.Border:SetAlpha(0)
            end
            if not GetFFD(dialogFrame).bg then
                local RS = CludesUI.RESKIN
                GetFFD(dialogFrame).bg = dialogFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
                GetFFD(dialogFrame).bg:SetAllPoints()
                GetFFD(dialogFrame).bg:SetColorTexture(RS.BG_R, RS.BG_G, RS.BG_B, RS.QT_ALPHA)
                GetFFD(GetFFD(dialogFrame).bg).owned = true
                if not _PP then
                    _PP = CludesUI and CludesUI.PP
                end
                if _PP and _PP.CreateBorder then
                    _PP.CreateBorder(dialogFrame, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
                end
            end
            SkinRoleCheckButton(_G.LFDRoleCheckPopupAcceptButton)
            SkinRoleCheckButton(_G.LFDRoleCheckPopupDeclineButton)
        end

        -- Not gated behind any LFG event: unlike the proposal/status popups above,
        -- this frame is part of the always-loaded base UI and can show independently
        -- of any Dungeon Finder UI ever being opened locally, so it is hooked directly.
        local _roleCheckHooked = false
        local function HookRoleCheckOnShow()
            if _roleCheckHooked then
                return
            end
            local dialogFrame = _G.LFDRoleCheckPopup
            if not dialogFrame then
                return
            end
            _roleCheckHooked = true
            dialogFrame:HookScript("OnShow", function()
                SkinRoleCheckPopup()
            end)
            -- Blizzard may have already called :Show() before we got here (e.g. a
            -- party member who never opened the LFG UI themselves) -- HookScript
            -- only catches future shows, so skin the current one too.
            if dialogFrame:IsShown() then
                SkinRoleCheckPopup()
            end
        end
        HookRoleCheckOnShow()

        local lfgFrame = CreateFrame("Frame")
        lfgFrame:RegisterEvent("LFG_PROPOSAL_SHOW")
        lfgFrame:RegisterEvent("LFG_PROPOSAL_FAILED")
        lfgFrame:RegisterEvent("LFG_PROPOSAL_SUCCEEDED")
        -- Fallback retry only: HookRoleCheckOnShow already ran once at load. If
        -- LFDRoleCheckPopup somehow didn't exist yet at that point, this catches it
        -- the first time a role check actually happens, before the popup shows.
        lfgFrame:RegisterEvent("LFG_ROLE_CHECK_SHOW")
        lfgFrame:SetScript("OnEvent", function(_, evt)
            if not CludesUIDB then
                return
            end
            if evt == "LFG_ROLE_CHECK_SHOW" then
                HookRoleCheckOnShow()
            elseif evt == "LFG_PROPOSAL_SHOW" then
                local reskinOn = IsQueueReskinOn()
                if reskinOn then
                    SkinQueuePopup()
                    HookStatusOnShow()
                end
                if CludesUIDB.showQueueTimer ~= false then
                    ShowQueueTimer(reskinOn)
                end
            else
                -- FAILED/SUCCEEDED: the status popup shows
                SkinQueueStatus()
            end
        end)
    end
end)()

Inner.last = "TooltipSkin"
