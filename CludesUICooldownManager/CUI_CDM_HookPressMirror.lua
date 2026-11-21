if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_CDM_HookPressMirror.lua
--
--  Mirror Key Presses, and the queued-attack highlight (WoW Forever), both
--  drawn like the action bars' own buttons.
--  Reads the earlier hook files through ns and ns._hookInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._hookInternals
-- CludesUICdmHooks.lua or an earlier hook file failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local barDataByKey = mod.barDataByKey
local cdmBarIcons = mod.cdmBarIcons
local _ecmeFC = mod._ecmeFC
local GetTime = GetTime

-------------------------------------------------------------------------------
--  Mirror Key Presses  (per-bar: barData.pressMirror -- set in CDM Bars > Extras)
--
--  Show the action-button "pushed down" look on a CDM bar icon whenever you
--  press that ability's keybind, even while on cooldown. Hooks the
--  action-button key-down path (ActionButtonDown/MultiActionButtonDown), which
--  fires on the physical press regardless of cooldown or the cast-on-key-
--  down/up CVar. Pushed texture + colour are read live from the CludesUI
--  action bars settings, so the CDM press matches real buttons (falling back
--  to a border-cropped Blizzard depress texture if that module isn't present).
--  On a custom-shape bar the press is masked to the shape, so a hexagon icon
--  flashes a hexagon rather than the full square it sits in.
--  Per-frame data lives in an external weak-keyed table.
-------------------------------------------------------------------------------
do
    local AB_MEDIA = "Interface\\AddOns\\CludesUIActionBars\\Media\\"
    local AB_HIGHLIGHT =
        { AB_MEDIA .. "highlight-2.png", AB_MEDIA .. "highlight-3.png", AB_MEDIA .. "highlight-4.png" }
    local DEPRESS_TEX = "Interface\\Buttons\\UI-Quickslot-Depress"
    local CHECKED_TEX = "Interface\\Buttons\\CheckButtonHilight"
    local CHECKED_ATLAS = "UI-HUD-ActionBar-IconFrame-Mouseover"
    local DEPRESS_INSET = 0.14 -- crop the beveled border off the fallback texture
    local MIN_VISIBLE = 0.05 -- floor so ultra-fast taps still show a press
    local MAX_HOLD = 2.0 -- safety: never leave an icon stuck "pressed"

    local _pushOverlay = setmetatable({}, { __mode = "k" }) -- [icon] = overlay frame
    local _held = {} -- [buttonFrame] = { overlays = {..}, keys = {..}, t = GetTime() }
    local _heldN = 0
    local _poll = mod.TakeShell()
    _poll:Hide()

    -- Read the action bars' pushed settings live so the CDM press matches them.
    local function GetABProfile()
        local L = CUI and CUI.Lite
        if not (L and L.GetAddon) then return nil end
        local success, eab = pcall(L.GetAddon, "CludesUIActionBars", true)
        if success and eab and eab.db then return eab.db.profile end
        return nil
    end

    -- Style tex to match the bars' pushed look. Returns false when pushed is set
    -- to "None" (so the CDM press mirrors that), "border" for border mode, true otherwise.
    local function StylePush(texture)
        local p = GetABProfile()
        if p then
            local pType = p.pushedTextureType or 2
            local color = p.pushedCustomColor or { r = 0.973, g = 0.839, b = 0.604 }
            local cr, cg, callback = color.r, color.g, color.b
            if p.pushedUseClassColor then
                local _, classTok = UnitClass("player")
                if classTok then
                    local cc = RAID_CLASS_COLORS[classTok]
                    if cc then
                        cr, cg, callback = cc.r, cc.g, cc.b
                    end
                end
            end
            texture:SetTexCoord(0, 1, 0, 1)
            if p.useClassicStyle then
                -- Classic WoW UI action bars: the vanilla pushed slot, uncropped.
                texture:SetAtlas(nil)
                texture:SetTexture(DEPRESS_TEX)
                texture:SetVertexColor(1, 1, 1, 1)
                texture:SetAlpha(1)
                return true
            elseif p.useBlizzardStyle then
                -- The bars' own pressed art: the retail sheet on WoW Forever
                -- (CludesUI.StockAtlas) unless the bars wear its own look.
                if CUI.IS_FOREVER == true and p.useForeverStyle == true then
                    texture:SetAtlas("UI-HUD-ActionBar-IconFrame-Down", false)
                else
                    CUI.StockAtlas(texture, "UI-HUD-ActionBar-IconFrame-Down", false)
                end
                texture:SetVertexColor(1, 1, 1, 1)
                texture:SetAlpha(1)
                return true
            elseif pType == 6 then
                texture:SetAlpha(0)
                return false
            elseif pType == 5 then
                texture:SetAlpha(0)
                return "border", cr, cg, callback, p.pushedBorderSize or 4
            end
            texture:SetAlpha(1)
            if pType <= 3 then
                texture:SetAtlas(nil)
                texture:SetTexture(AB_HIGHLIGHT[pType] or AB_HIGHLIGHT[2])
                texture:SetVertexColor(cr, cg, callback, 1)
            elseif pType == 4 then
                texture:SetColorTexture(cr, cg, callback, 0.35)
            end
            return true
        end
        -- Fallback: interior of the Blizzard depress texture (border cropped off).
        texture:SetAtlas(nil)
        texture:SetTexture(DEPRESS_TEX)
        texture:SetTexCoord(DEPRESS_INSET, 1 - DEPRESS_INSET, DEPRESS_INSET, 1 - DEPRESS_INSET)
        texture:SetVertexColor(1, 1, 1, 1)
        texture:SetAlpha(1)
        return true
    end

    -- Style tex as the bars' spell cast highlight (their CheckedTexture, drawn
    -- additive in every look): CludesUI's highlight art, the Classic button
    -- art or Blizzard's own (WoW Forever's while the bars wear that look), and
    -- nothing while Show Highlight on Spell Cast is off. Show as Border swaps
    -- the fill only on bars with a textured border, so a fill stands here.
    -- Without the action bars: Blizzard's own art, as its bars show it.
    local function StyleChecked(texture)
        local p = GetABProfile()
        if p and p.showCastHighlight == false then
            texture:SetAlpha(0)
            return false
        end
        texture:SetTexCoord(0, 1, 0, 1)
        texture:SetVertexColor(1, 1, 1, 1)
        texture:SetAlpha(1)
        texture:SetBlendMode("ADD")
        if not p then
            texture:SetAtlas(CHECKED_ATLAS, false)
        elseif p.useClassicStyle then
            texture:SetAtlas(nil)
            texture:SetTexture(CHECKED_TEX)
        elseif p.useBlizzardStyle then
            if CUI.IS_FOREVER == true and p.useForeverStyle == true then
                texture:SetAtlas(CHECKED_ATLAS, false)
            else
                CUI.StockAtlas(texture, CHECKED_ATLAS, false)
            end
        else
            texture:SetAtlas(nil)
            texture:SetTexture(AB_HIGHLIGHT[1])
        end
        return true
    end

    local function EnsureBorderEdges(shade)
        if shade._borderEdges then return shade._borderEdges end
        local edges = {}
        for jdx = 1, 4 do
            local tex = shade:CreateTexture(nil, "OVERLAY", nil, 2)
            tex:SetColorTexture(1, 1, 1, 1)
            tex:Hide()
            edges[jdx] = tex
        end
        shade._borderEdges = edges
        return edges
    end

    -- Custom shape of a CDM icon (hexagon/circle/...), or nil for a square one.
    -- A square press drawn over a shaped icon spills past the shape, so the
    -- overlay has to follow it. We reuse the icon's own shapeMask -- masking is
    -- screen-space and the overlay covers the same rect -- exactly like the
    -- fake-active overlay does (ns.ApplyShapeToOverlay). none/cropped return
    -- nil: their icon art fills the frame rect, so a square press is correct.
    local function IconShape(iconTex)
        local ifc = _ecmeFC and _ecmeFC[iconTex]
        if not (ifc and ifc.shapeApplied and ifc.shapeMask) then return nil end
        local shape = ifc.shapeName
        if not shape or shape == "none" or shape == "cropped" then return nil end
        return shape, ifc.shapeMask
    end

    -- Ring art for "border" pushed mode on a shaped icon: four straight edges
    -- around a hexagon leave the corners hanging in space, so press-flash the
    -- shape's own border texture instead. Its thickness is baked into the art,
    -- so the bars' pushed border size doesn't apply -- colour still does.
    local function EnsureShapeRing(shade)
        if shade._shapeRing then return shade._shapeRing end
        local tex = shade:CreateTexture(nil, "OVERLAY", nil, 2)
        tex:SetSnapToPixelGrid(false)
        tex:SetTexelSnappingBias(0)
        tex:Hide()
        shade._shapeRing = tex
        return tex
    end

    -- One overlay per icon in `store`, `level` above the icon (above the
    -- cooldown swipe), fitted to the icon's shape and styled by `style`, which
    -- returns false (nothing to show), "border" + r, g, b, size, or true.
    local function ShowOverlay(iconTex, storage, level, style)
        local shade = storage[iconTex]
        if not shade then
            shade = CreateFrame("Frame", nil, iconTex)
            shade:SetFrameLevel(iconTex:GetFrameLevel() + level)
            shade:Hide()
            local texture = shade:CreateTexture(nil, "OVERLAY")
            texture:SetAllPoints(shade)
            shade._tex = texture
            storage[iconTex] = shade
        end
        -- Re-sync the shape mask on every press: the shape can change or be
        -- cleared between presses, and a cleared shapeMask is emptied + hidden
        -- rather than destroyed -- left attached it would blank the overlay.
        -- A shape swap keeps the same mask object (re-textured), so it stays.
        local shape, mask = IconShape(iconTex)
        if shade._shapeMask and shade._shapeMask ~= mask then
            pcall(shade._tex.RemoveMaskTexture, shade._tex, shade._shapeMask)
            shade._shapeMask = nil
        end
        if mask and not shade._shapeMask then
            pcall(shade._tex.AddMaskTexture, shade._tex, mask)
            shade._shapeMask = mask
        end
        -- Blizzard Style: the flash rounds off with the icon's viewer mask.
        if mod.CdmBlizzIcons() then
            local bm = mod.CdmBlizzIconMask(iconTex)
            if bm and shade._blizzMask ~= bm then
                pcall(shade._tex.AddMaskTexture, shade._tex, bm)
                shade._blizzMask = bm
            end
        end
        local result, cr, cg, callback, bsz = style(shade._tex)
        if not result then
            shade:Hide()
            return nil
        end
        -- Shaped icons expand their icon texture past the frame (and expand the
        -- texcoords to match), so anchor to the frame itself -- the rect the
        -- shapeMask covers -- rather than to the oversized texture.
        local regionFrame = (shape and iconTex) or iconTex.Icon or iconTex
        shade:ClearAllPoints()
        shade:SetPoint("TOPLEFT", regionFrame, "TOPLEFT", 0, 0)
        shade:SetPoint("BOTTOMRIGHT", regionFrame, "BOTTOMRIGHT", 0, 0)
        local ringTex = shape and mod.CDM_SHAPE_BORDERS and mod.CDM_SHAPE_BORDERS[shape]
        if result == "border" and ringTex then
            shade._tex:Hide()
            if shade._borderEdges then
                for jdx = 1, 4 do
                    shade._borderEdges[jdx]:Hide()
                end
            end
            local ring = EnsureShapeRing(shade)
            ring:SetTexture(ringTex)
            ring:SetVertexColor(cr, cg, callback, 1)
            ring:ClearAllPoints()
            ring:SetAllPoints(shade)
            ring:Show()
        elseif result == "border" then
            shade._tex:Hide()
            if shade._shapeRing then shade._shapeRing:Hide() end
            local edges = EnsureBorderEdges(shade)
            for jdx = 1, 4 do
                edges[jdx]:SetVertexColor(cr, cg, callback, 1)
            end
            edges[1]:ClearAllPoints()
            edges[1]:SetPoint("TOPLEFT", shade)
            edges[1]:SetPoint("TOPRIGHT", shade)
            edges[1]:SetHeight(bsz)
            edges[1]:Show()
            edges[2]:ClearAllPoints()
            edges[2]:SetPoint("BOTTOMLEFT", shade)
            edges[2]:SetPoint("BOTTOMRIGHT", shade)
            edges[2]:SetHeight(bsz)
            edges[2]:Show()
            edges[3]:ClearAllPoints()
            edges[3]:SetPoint("TOPLEFT", edges[1], "BOTTOMLEFT")
            edges[3]:SetPoint("BOTTOMLEFT", edges[2], "TOPLEFT")
            edges[3]:SetWidth(bsz)
            edges[3]:Show()
            edges[4]:ClearAllPoints()
            edges[4]:SetPoint("TOPRIGHT", edges[1], "BOTTOMRIGHT")
            edges[4]:SetPoint("BOTTOMRIGHT", edges[2], "TOPRIGHT")
            edges[4]:SetWidth(bsz)
            edges[4]:Show()
        else
            shade._tex:Show()
            if shade._borderEdges then
                for jdx = 1, 4 do
                    shade._borderEdges[jdx]:Hide()
                end
            end
            if shade._shapeRing then shade._shapeRing:Hide() end
        end
        shade:Show()
        return shade
    end

    local function ShowPush(iconTex) return ShowOverlay(iconTex, _pushOverlay, 15, StylePush) end

    ---------------------------------------------------------------------------
    --  Spell matching (pressed button's spell vs. a CDM icon's spell)
    ---------------------------------------------------------------------------
    local GetOverrideSpell = C_Spell and C_Spell.GetOverrideSpell
    local GetBaseSpell = C_Spell and C_Spell.GetBaseSpell
    local FindSpellOverrideByID = C_SpellBook and C_SpellBook.FindSpellOverrideByID

    local function safeNum(func, arg)
        if type(func) ~= "function" then return nil end
        local success, res = pcall(func, arg)
        if success and type(res) == "number" and res > 0 then return res end
    end

    local function SpellIdSet(ident)
        local tbl = { [ident] = true }
        local a = safeNum(GetOverrideSpell, ident)
        if a then tbl[a] = true end
        local b = safeNum(GetBaseSpell, ident)
        if b then tbl[b] = true end
        local c = safeNum(FindBaseSpellByID, ident)
        if c then tbl[c] = true end
        local skinData = safeNum(FindSpellOverrideByID, ident)
        if skinData then tbl[skinData] = true end
        return tbl
    end

    local function IconMatches(pressedSet, iconSid)
        if pressedSet[iconSid] then return true end
        local a = safeNum(GetOverrideSpell, iconSid)
        if a and pressedSet[a] then return true end
        local b = safeNum(GetBaseSpell, iconSid)
        if b and pressedSet[b] then return true end
        return false
    end

    -- Reverse lookup: the primary itemID of the item preset that owns a given
    -- alt/current-tier itemID (e.g. Concentrated Health Potion 271884 ->
    -- 241304). Bar icons for these presets always key off the fixed primary
    -- id (see silvermoon_health's itemID/altItemIDs split), but a press can
    -- report any owned tier's itemID, so OnPress needs to resolve it back.
    local _presetPrimaryByAltID
    local function PresetPrimaryItemID(itemId)
        if not _presetPrimaryByAltID then
            _presetPrimaryByAltID = {}
            for _, pr in ipairs(mod.CDM_ITEM_PRESETS or {}) do
                if pr.altItemIDs then
                    for _, alt in ipairs(pr.altItemIDs) do
                        _presetPrimaryByAltID[alt] = pr.itemID
                    end
                end
            end
        end
        return _presetPrimaryByAltID[itemId]
    end

    local function IconSpellID(iconTex)
        local fc = _ecmeFC and _ecmeFC[iconTex]
        local spellRef = fc and fc.spellID
        if spellRef then return spellRef end
        local cdID = iconTex.cooldownID
        if cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
            local details = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
            if details then return details.overrideSpellID or details.spellID end
        end
        return nil
    end

    ---------------------------------------------------------------------------
    --  Press / hold / release. Release is driven by polling IsKeyDown on the
    --  button's binding keys, floored by MIN_VISIBLE and capped by MAX_HOLD.
    ---------------------------------------------------------------------------
    local function ReleaseEntry(button, record)
        local ovs = record.overlays
        for index = 1, #ovs do
            ovs[index]:Hide()
        end
        _held[button] = nil
        _heldN = _heldN - 1
        if _heldN <= 0 then
            _heldN = 0
            _poll:Hide()
        end
    end

    _poll:SetScript("OnUpdate", function()
        if _heldN == 0 then
            _poll:Hide()
            return
        end
        local nowTime = GetTime()
        for button, record in pairs(_held) do
            local elapsed = nowTime - record.t
            local done = false
            if elapsed >= MAX_HOLD then
                done = true
            elseif elapsed >= MIN_VISIBLE then
                local anyDown = false
                local keyList = record.keys
                if keyList then
                    for index = 1, #keyList do
                        if keyList[index] and IsKeyDown(keyList[index]) then
                            anyDown = true
                            break
                        end
                    end
                end
                if not anyDown then done = true end
            end
            if done then ReleaseEntry(button, record) end
        end
    end)

    -- Cached enable-flag so OnPress can gate in O(1) instead of looping every
    -- bar on each key press (the ActionButtonDown hook fires for all users).
    -- Recomputed only when the bar list is rebuilt (RefreshCdmPressMirrorFlag,
    -- called from the CDM bar-rebuild pass) or when the toggle changes.
    local _anyPressMirror = false
    local function RefreshCdmPressMirrorFlag()
        _anyPressMirror = false
        if not barDataByKey then return end
        for _, edge in pairs(barDataByKey) do
            -- Buff-family bars never mirror presses (auto-tracked auras, not
            -- keybind-pressed), so ignore a stale/imported pressMirror on them.
            if edge and edge.pressMirror and not mod.IsBarBuffFamily(edge) then
                _anyPressMirror = true
                return
            end
        end
    end
    mod.RefreshCdmPressMirrorFlag = RefreshCdmPressMirrorFlag
    RefreshCdmPressMirrorFlag()

    local function SlotSpellID(slot)
        if not slot then return nil end
        if HasAction and not HasAction(slot) then return nil end
        -- NOTE (Midnight): GetActionInfo is documented as usable only in the
        -- secure restricted environment. This runs from an insecure post-hook,
        -- so a future build could hand back nil/secret here and silently no-op
        -- the press mirror. Revisit via a secure route if that ever regresses.
        local actionType, ident, subType = GetActionInfo(slot)
        if actionType == "spell" then
            return ident
        elseif actionType == "item" then
            -- On-use trinkets/potions/healthstones placed directly on the
            -- action bar: hand back the itemID as a second return. Bar icons
            -- for these track by NEGATIVE identity (-itemID for item presets,
            -- -invSlot for "whatever's equipped in slot X" -- see
            -- ns.INV_SLOT_NAMES / the <= -100 item-preset branch above), not a
            -- resolved spellID, so the caller builds the matching keys itself.
            return nil, ident
        elseif actionType == "macro" then
            if subType == "spell" then
                return ident
            elseif subType == "item" then
                return nil
            end
            local macroName = GetActionText(slot)
            local macroIndex = macroName and GetMacroIndexByName(macroName)
            if macroIndex and macroIndex > 0 then
                if GetMacroItem and GetMacroItem(macroIndex) then return nil end
                return GetMacroSpell(macroIndex)
            end
        end
        return nil
    end
    mod.SlotSpellID = SlotSpellID

    -- Base key of a (possibly modified) binding, e.g. "SHIFT-1" -> "1".
    local function BaseKey(binding) return binding and binding:match("[^%-]+$") or nil end

    local function OnPress(button, bindCmd)
        if not button or not _anyPressMirror then return end
        local slot = button.action or (button.GetAttribute and button:GetAttribute("action"))
        local spellRef, itemId = SlotSpellID(slot)
        if not spellRef and not itemId then return end

        local pressedSet = spellRef and SpellIdSet(spellRef) or {}
        if itemId then
            -- Item-preset icons (potions, healthstones, custom item ids) key
            -- off -itemID; equipment-slot icons (trinkets -13/-14, or any
            -- user-added slot) key off -invSlot for whatever's equipped there.
            -- Match both, plus the item's own on-use spell for the rarer case
            -- of it being tracked as a plain Custom Spell entry instead.
            pressedSet[-itemId] = true
            local primaryItemID = PresetPrimaryItemID(itemId)
            if primaryItemID then pressedSet[-primaryItemID] = true end
            for invSlot in pairs(mod.INV_SLOT_NAMES) do
                if GetInventoryItemID("player", invSlot) == itemId then pressedSet[-invSlot] = true end
            end
            local _, useSpellID = C_Item.GetItemSpell(itemId)
            if useSpellID then
                for key in pairs(SpellIdSet(useSpellID)) do
                    pressedSet[key] = true
                end
            end
        end
        local overlays
        if cdmBarIcons then
            for barId, entries in pairs(cdmBarIcons) do
                local edge = barDataByKey and barDataByKey[barId]
                if edge and edge.pressMirror and not mod.IsBarBuffFamily(edge) then
                    for index = 1, #entries do
                        local iconTex = entries[index]
                        if iconTex and iconTex:IsShown() then
                            local isid = IconSpellID(iconTex)
                            if isid and IconMatches(pressedSet, isid) then
                                local shade = ShowPush(iconTex)
                                if shade then
                                    overlays = overlays or {}
                                    overlays[#overlays + 1] = shade
                                end
                            end
                        end
                    end
                end
            end
        end
        if not overlays then return end

        local keyList
        if bindCmd then
            local k1, k2 = GetBindingKey(bindCmd)
            keyList = { BaseKey(k1), BaseKey(k2) }
        end
        local record = _held[button]
        if record then
            record.overlays = overlays
            record.keys = keyList
            record.t = GetTime()
        else
            _held[button] = { overlays = overlays, keys = keyList, t = GetTime() }
            _heldN = _heldN + 1
        end
        _poll:Show()
    end

    -- Public: clear active overlays (called from the CDM Bars > Extras toggle).
    function mod.ClearCdmPressPush()
        for _, record in pairs(_held) do
            local ovs = record.overlays
            for index = 1, #ovs do
                ovs[index]:Hide()
            end
        end
        wipe(_held)
        _heldN = 0
        _poll:Hide()
        RefreshCdmPressMirrorFlag()
    end

    -- Click-routed keybinds (Bars 9/10, empower spells, custom paging) go
    -- through the button via SetOverrideBindingClick and never fire the native
    -- commands hooked below; the EAB PostClick hook publishes them here.
    -- PostClick runs after Blizzard's click handler returns, downstream of its
    -- protected item-use calls -- same taint posture as the native hooks.
    _G._CUI_OnActionButtonPress = function(button, down, bindCmd)
        -- Down edge only: buttons register both edges, and in key-up mode the
        -- key is already released by the up click.
        if not down or not button or not bindCmd or not _anyPressMirror then return end
        -- Keyboard evidence (a real mouse click must not mirror): a held
        -- binding key proves keyboard, but wheel binds are never IsKeyDown, so
        -- the cursor-rect test covers those. Only miss: a wheel bind pressed
        -- while the cursor rests on its own button.
        local k1, k2 = GetBindingKey(bindCmd)
        local b1, b2 = BaseKey(k1), BaseKey(k2)
        local keyHeld = (b1 and IsKeyDown(b1)) or (b2 and IsKeyDown(b2))
        if not keyHeld and button.IsUnderMouse and button:IsUnderMouse() then return end
        OnPress(button, bindCmd)
    end

    ---------------------------------------------------------------------------
    --  Hook the action-button key-down path (fires on press, even on cooldown)
    ---------------------------------------------------------------------------
    local MULTIBAR_BINDING = {
        MultiBarBottomLeft = "MULTIACTIONBAR1BUTTON",
        MultiBarBottomRight = "MULTIACTIONBAR2BUTTON",
        MultiBarRight = "MULTIACTIONBAR3BUTTON",
        MultiBarLeft = "MULTIACTIONBAR4BUTTON",
        MultiBar5 = "MULTIACTIONBAR5BUTTON",
        MultiBar6 = "MULTIACTIONBAR6BUTTON",
        MultiBar7 = "MULTIACTIONBAR7BUTTON",
    }

    local ev = mod.TakeShell()
    ev:RegisterEvent("PLAYER_LOGIN")
    ev:SetScript("OnEvent", function()
        if type(ActionButtonDown) == "function" then
            hooksecurefunc("ActionButtonDown", function(ident)
                local button = (GetActionButtonForID and GetActionButtonForID(ident))
                    or _G["ActionButton" .. ident]
                OnPress(button, "ACTIONBUTTON" .. ident)
            end)
        end
        if type(MultiActionButtonDown) == "function" then
            hooksecurefunc("MultiActionButtonDown", function(barName, ident)
                local prefixText = MULTIBAR_BINDING[barName]
                OnPress(_G[barName .. "Button" .. ident], prefixText and (prefixText .. ident) or nil)
            end)
        end
    end)

    ---------------------------------------------------------------------------
    --  Queued attacks (WoW Forever): while an on-next-swing attack is queued
    --  (CludesUI.FOREVER_NEXT_SWING: Heroic Strike, Cleave, Maul, Raptor
    --  Strike), its CDM icons show the action bars' spell cast highlight, as
    --  the bar button holding it does. ACTIONBAR_UPDATE_STATE, the edge those
    --  buttons check on, is registered only for a class that has such an
    --  attack; a burst folds into one pass on the next frame, which repaints
    --  only when the queued attack changed. A restricted answer counts as not
    --  queued.
    ---------------------------------------------------------------------------
    local _checkOverlay = setmetatable({}, { __mode = "k" }) -- [icon] = overlay frame
    local _queueNames -- the class's attack names, resolved at login
    local _queued = false -- the name painted, false = none
    local _lit = {} -- the overlays showing it
    local _queueFlush = mod.TakeShell()
    _queueFlush:Hide()
    _queueFlush:SetScript("OnUpdate", function(self)
        self:Hide()
        local name = false
        for index = 1, #_queueNames do
            local current = C_Spell.IsCurrentSpell(_queueNames[index])
            if not issecretvalue(current) and current then
                name = _queueNames[index]
                break
            end
        end
        if name == _queued then return end
        _queued = name
        for index = #_lit, 1, -1 do
            _lit[index]:Hide()
            _lit[index] = nil
        end
        if not (name and cdmBarIcons) then return end
        for barId, entries in pairs(cdmBarIcons) do
            local edge = barDataByKey and barDataByKey[barId]
            if edge and not mod.IsBarBuffFamily(edge) then
                for index = 1, #entries do
                    local iconTex = entries[index]
                    if iconTex and iconTex:IsShown() then
                        local spellRef = IconSpellID(iconTex)
                        if
                            not issecretvalue(spellRef)
                            and spellRef
                            and C_Spell.GetSpellName(spellRef) == name
                        then
                            local shade = ShowOverlay(iconTex, _checkOverlay, 14, StyleChecked)
                            if shade then _lit[#_lit + 1] = shade end
                        end
                    end
                end
            end
        end
    end)

    local qev = mod.TakeShell()
    qev:RegisterEvent("PLAYER_LOGIN")
    qev:SetScript("OnEvent", function(self, evt)
        if evt ~= "PLAYER_LOGIN" then
            _queueFlush:Show()
            return
        end
        self:UnregisterEvent("PLAYER_LOGIN")
        local lists = CUI.FOREVER_NEXT_SWING
        local _, class = UnitClass("player")
        local ids = lists and lists[class]
        if not (ids and C_Spell.IsCurrentSpell) then return end
        _queueNames = {}
        for index = 1, #ids do
            local num = C_Spell.GetSpellName(ids[index])
            if not issecretvalue(num) and num then _queueNames[#_queueNames + 1] = num end
        end
        if #_queueNames > 0 then self:RegisterEvent("ACTIONBAR_UPDATE_STATE") end
    end)
end
Inner.broken = false
