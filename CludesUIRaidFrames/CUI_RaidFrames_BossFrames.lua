if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_RaidFrames_BossFrames.lua
--
--  Friendly Boss Frames: five secure unit buttons for boss1 to boss5.
--  Reads the earlier Raid Frames files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIRaidFrames.lua or an earlier Raid Frames file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local ipairs = ipairs
local wipe = wipe
local UnitClass = UnitClass
local UnitExists = UnitExists
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsConnected = UnitIsConnected
local UnitIsUnit = UnitIsUnit
local IsInRaid = IsInRaid
local InCombatLockdown = InCombatLockdown
local GetNumGroupMembers = GetNumGroupMembers
local C_Timer = C_Timer
local issecretvalue = issecretvalue
local CreateFrame = CreateFrame

local GetFFD, PixelSnap = Inner.GetFFD, Inner.PixelSnap
local ResolveHealthTexture, separatedHdrs = Inner.ResolveHealthTexture, Inner.separatedHdrs
local GetSafeHealthPercent = Inner.GetSafeHealthPercent

local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(val)
    saved = val
end
local Pix
Inner.PPSetters[#Inner.PPSetters + 1] = function(val)
    Pix = val
end

-------------------------------------------------------------------------------
--  Friendly Boss Frames (any group): five standalone secure unit buttons for
--  boss1-boss5. A secure visibility driver on [@bossN,help] is the entire
--  detection (encounters expose healable friendly NPCs as boss units) -- no
--  NPC database, fully combat safe. Dungeon encounters use the same boss unit
--  tokens as raids, so the group gate can cover party too -- behind the Show
--  in Dungeons opt-in (fb.showInDungeons, default off); attached positions
--  slot in beside the party container there. Buttons render ONLY health bar +
--  name/health text, following the RAID frame settings in a party too (one
--  styled group, and the indicator containers are built once). Excluded from preview and
--  unlock mode (Free Move uses its own drag overlay). Display "healers"
--  builds/activates only on a healer spec.
-------------------------------------------------------------------------------
-- do/end scope; closures below keep FB alive after the block closes.
do
    local FB = { buttons = {}, trackers = {} }
    mod._FB = FB

    -- Settings source per button for the other groups these helpers style (the pet frames beside the
    -- party frames read the party settings). Unregistered buttons, the boss group's own among them,
    -- read the raid settings.
    FB.src = setmetatable({}, { __mode = "k" })
    FB.Source = function(b)
        local get = FB.src[b]
        return (get and get()) or mod._scaledProfile or saved.profile
    end

    -- Target store: true while a button shows your target, read by the border painter. Re-read by the
    -- full paint and on target changes, so a target change repaints only the buttons that flipped.
    -- UnitIsUnit can be secret: read as not targeted. Returns true when the button's state flipped.
    FB.tgt = setmetatable({}, { __mode = "k" })
    FB.ReadTarget = function(b, unitToken)
        local t = unitToken and UnitIsUnit(unitToken, "target")
        if issecretvalue(t) then
            t = false
        end
        t = t and true or nil
        if FB.tgt[b] == t then
            return false
        end
        FB.tgt[b] = t
        return true
    end

    -- Hover store: true while the mouse is over a button, read by the border painter.
    FB.hov = setmetatable({}, { __mode = "k" })

    -- Baseline heal per healer class for NPC range checks. Boss units sit outside UnitInRange's
    -- group-member domain and never fire UNIT_IN_RANGE_UPDATE, so range is measured against a known
    -- helpful spell instead -- healer specs only; everyone else keeps full alpha (no range check).
    FB.RANGE_HEAL = {
        PRIEST = 2061, -- Flash Heal
        PALADIN = 19750, -- Flash of Light
        SHAMAN = 8004, -- Healing Surge
        DRUID = 8936, -- Regrowth
        MONK = 116670, -- Vivify
        EVOKER = 361469, -- Living Flame (25yd: native Evoker range)
    }

    -- WoW Forever: the class's best heal the spellbook holds (CludesUI.FOREVER_HEAL_SPELLS, best
    -- first); nil when the class has none or has not learned one yet.
    FB.ForeverKnownHeal = function(pClass)
        local entries = CludesUI.FOREVER_HEAL_SPELLS[pClass]
        if not entries then
            return nil
        end
        local bank = C_SpellBook and C_SpellBook.IsSpellInSpellBook and Enum.SpellBookSpellBank
        for index = 1, #entries do
            local ident = entries[index]
            local known
            if bank then
                known = C_SpellBook.IsSpellInSpellBook(ident, bank.Player, true)
            else
                known = IsSpellKnown and IsSpellKnown(ident)
            end
            if known then
                return ident
            end
        end
        return nil
    end

    -- Secret-safe alpha application (result may be secret in instances, which SetAlphaFromBoolean
    -- accepts natively). The result can also be NIL (unit not range-checkable / spell momentarily not
    -- evaluable), which it rejects -- treat NIL as in range. issecretvalue runs FIRST so the nil check
    -- never touches a secret.
    FB.ApplyRange = function(widget)
        if not FB.rangeSpell then
            return
        end
        local cfg = mod._scaledProfile or saved.profile
        local inRange = C_Spell.IsSpellInRange(FB.rangeSpell, FB.UnitOf(widget))
        if issecretvalue(inRange) or inRange ~= nil then
            widget:SetAlphaFromBoolean(inRange, 1, cfg.oorAlpha or 0.4)
        else
            widget:SetAlpha(1)
        end
    end

    FB.RangeTick = function()
        for _, btn in ipairs(FB.buttons) do
            if btn:IsVisible() then
                FB.ApplyRange(btn)
            end
        end
    end

    -- The ticker exists only while a range spell is resolved AND at least one boss button is visible -- zero idle cost.
    FB.UpdateRangeTicker = function()
        local wanted = FB.rangeSpell and (FB.visCount or 0) > 0
        if wanted and not FB.rangeTicker then
            FB.rangeTicker = C_Timer.NewTicker(0.4, FB.RangeTick)
        elseif not wanted and FB.rangeTicker then
            FB.rangeTicker:Cancel()
            FB.rangeTicker = nil
        end
    end

    -- Current unit for a button. The slot controller collapses friendly bosses into the FIRST slots
    -- (slot 1 may show boss2), so the secure "unit" attribute is truth; _fbUnit is the build default.
    FB.UnitOf = function(widget)
        return widget:GetAttribute("unit") or widget._fbUnit
    end

    FB.Settings = function()
        return saved and saved.profile and saved.profile.friendlyBoss
    end

    FB.ShouldBeActive = function()
        local fallback = FB.Settings()
        if not fallback then
            return false
        end
        -- Arena never has friendly bosses; an empty group there only takes room beside the party frames.
        if mod._InArena() then
            return false
        end
        if fallback.display == "always" then
            return true
        end
        if fallback.display == "healers" then
            -- WoW Forever: a class that can heal counts as its healing spec.
            if CludesUI.IS_FOREVER then
                local _, pClass = UnitClass("player")
                return CludesUI.FOREVER_HEAL_SPELLS[pClass] ~= nil
            end
            local specInfo = GetSpecialization and GetSpecialization()
            local role = specInfo and GetSpecializationRole and GetSpecializationRole(specInfo)
            return role == "HEALER"
        end
        return false
    end

    -- Recolor the border for the current state. Mirrors the raid buttons' single recolored border:
    -- hover (raised) > target (raised) > normal, using the button's border settings (FB.Source: the raid
    -- ones for the boss group) -- nothing separate.
    FB.ApplyBorderColor = function(widget)
        if not Pix or not widget._borderFrame or not saved then
            return
        end
        local cfg = FB.Source(widget)
        local targeted = FB.tgt[widget] and cfg.targetBorderEnabled ~= false
        if mod.RF_PetCompactOn(widget, cfg) then
            mod.RF_PetCompactHighlight(widget, cfg)
            return
        end
        if widget.stockEdge then
            local hover = FB.hov[widget] and cfg.hoverBorderEnabled ~= false
            local lvl = widget:GetFrameLevel() + (hover and mod.LVL_RAISE or 8)
            if widget._borderFrame:GetFrameLevel() ~= lvl then
                widget._borderFrame:SetFrameLevel(lvl)
                local boxHolder = Pix.GetBorders(widget._borderFrame)
                if boxHolder then
                    boxHolder:SetFrameLevel(lvl + 1)
                end
            end
            mod.RF_StockHighlight(widget, widget._borderFrame, cfg, hover, targeted)
            return
        end
        local region, g, bcol, a
        local raised, hlSize, hlPx = false, nil, nil
        if FB.hov[widget] and cfg.hoverBorderEnabled ~= false then
            local color = cfg.hoverBorderColor or { r = 1, g = 1, b = 1 }
            region, g, bcol, a = color.r, color.g, color.b, cfg.hoverBorderAlpha or 1
            raised, hlSize = true, cfg.hoverBorderSize or 1
            hlPx = CludesUI.BorderPx(cfg.hoverBorderSizePx, hlSize, cfg.borderTexture or "solid")
        elseif targeted then
            local color = cfg.targetBorderColor or { r = 1, g = 1, b = 1 }
            region, g, bcol, a = color.r, color.g, color.b, cfg.targetBorderAlpha or 1
            raised, hlSize = true, cfg.targetBorderSize or 1
            hlPx = CludesUI.BorderPx(cfg.targetBorderSizePx, hlSize, cfg.borderTexture or "solid")
        else
            local color = cfg.borderColor or { r = 0, g = 0, b = 0 }
            region, g, bcol, a = color.r, color.g, color.b, cfg.borderAlpha or 1
        end
        -- Raise above neighbors while highlighted (as the raid buttons: overlapping frames would cover it).
        local pl = widget:GetFrameLevel()
        local lvl = cfg.borderBehind and math.max(0, pl - 1) or (pl + (raised and mod.LVL_RAISE or 8))
        -- The container too, like ApplyBorderLevel: FB.StyleBorder moves only the border
        -- frame, so a Show Behind flip would otherwise leave the strips on the old level.
        local boxHolder = Pix.GetBorders(widget._borderFrame)
        if widget._borderFrame:GetFrameLevel() ~= lvl or (boxHolder and boxHolder:GetFrameLevel() ~= lvl + 1) then
            widget._borderFrame:SetFrameLevel(lvl)
            if boxHolder then
                boxHolder:SetFrameLevel(lvl + 1)
            end
            -- Textured styles: the backdrop child too (see ApplyBorderLevel).
            local edge = CludesUI._bdBorderData and CludesUI._bdBorderData[widget._borderFrame]
            if edge then
                edge:SetFrameLevel(lvl)
            end
        end
        if (cfg.borderSize or 1) <= 0 then
            mod.ApplyHighlightBorder(widget._borderFrame, cfg, hlSize, region, g, bcol, a, hlPx)
            return
        end
        if hlSize then
            region, g, bcol = mod.RF_VisibleHighlight(cfg, region, g, bcol)
        end
        widget._borderFrame._hlBorderSize = nil
        CludesUI.SetBorderStyleColor(widget._borderFrame, region, g, bcol, a)
    end

    -- Apply the border style (size/color/texture/offsets) to one button, from its FB.Source.
    FB.StyleBorder = function(widget)
        if not Pix or not widget._borderFrame then
            return
        end
        local cfg = FB.Source(widget)
        local bs = cfg.borderSize or 1
        local bc = cfg.borderColor or { r = 0, g = 0, b = 0 }
        local pl = widget:GetFrameLevel()
        local skinData = Inner.FFD[widget]
        local compact = mod.RF_PetCompactOn(widget, cfg)
        if compact or (skinData and skinData._petCompactBorder) then
            skinData._petCompactBorder = compact
        end
        if compact then
            CludesUI.ApplyBorderStyle(widget._borderFrame, 0, 0, 0, 0, 0, "solid")
            FB.ApplyBorderColor(widget)
            CludesUI.RoundCorners(widget, 0)
            return
        end
        if widget.stockEdge then
            widget._borderFrame:SetFrameLevel(pl + 8)
            CludesUI.ApplyBorderStyle(widget._borderFrame, 0, 0, 0, 0, 0, "solid")
            widget._borderFrame._hlBorderSize = nil
            mod.RF_StockSeat(widget)
            FB.ApplyBorderColor(widget)
            CludesUI.RoundCorners(widget, 0)
            return
        end
        widget._borderFrame:SetFrameLevel(cfg.borderBehind and math.max(0, pl - 1) or (pl + 8))
        CludesUI.ApplyBorderStyle(
            widget._borderFrame,
            bs,
            bc.r,
            bc.g,
            bc.b,
            cfg.borderAlpha or 1,
            cfg.borderTexture or "solid",
            cfg.borderTextureOffset,
            cfg.borderTextureOffsetY,
            cfg.borderTextureShiftX,
            cfg.borderTextureShiftY,
            "unitframes",
            bs,
            nil,
            CludesUI.BorderPx(cfg.borderSizePx, bs, cfg.borderTexture or "solid")
        )
        FB.ApplyBorderColor(widget)
        -- Rounded corners with the owner's Corner Radius, as on the raid cells
        -- (CludesUI_RoundedCorners.lua; nothing at radius 0).
        local radius = cfg.cornerRadius or 0
        if radius > 0 then
            CludesUI.RoundCorners(widget, radius, {
                roots = { widget._health },
                textures = { widget._bg },
                border = widget._borderFrame,
                style = cfg.borderTexture or "solid",
                corners = cfg.cornerMask,
            })
        else
            CludesUI.RoundCorners(widget, 0)
        end
    end

    -- Bar colour: the owner's own colour setting (default #17AC31). The raid color modes mislead here:
    -- gradient modes read as damage states, and many NPCs carry real class tokens (a friendly add can
    -- come out yellow).
    FB.PaintBarColor = function(b, ownerFrame, cfg)
        local healthBar = b._health
        local fbc = (ownerFrame.ColorSettings or ownerFrame.Settings)()
        fbc = fbc and fbc.healthColor
        local fillTex = healthBar:GetStatusBarTexture()
        if fillTex then
            fillTex:SetAlpha(1)
        end
        healthBar:SetStatusBarColor(
            fbc and fbc.r or 23 / 255,
            fbc and fbc.g or 172 / 255,
            fbc and fbc.b or 49 / 255,
            (cfg.healthBarOpacity or 100) / 100
        )
    end

    -- Text state of a button built with its texts (FB.BuildVisuals): the FontStrings, the
    -- plan and the settings they were last painted with, kept off the (possibly header-made) button.
    FB.txs = setmetatable({}, { __mode = "k" })

    -- Name texts only (name events).
    FB.PaintName = function(b, unitToken, s)
        local st = FB.txs[b]
        if not st then
            return
        end
        mod._RFTextReady(st, s)
        mod.RF_TextNames(st, unitToken)
    end

    -- Health value and the texts. full: the full paint (every text); otherwise a health event,
    -- which repaints Health and Heal Absorb Text and every Custom text: these trackers carry health
    -- and name events only, so Custom's power, absorb, group and target tags refresh here, not on
    -- their own events. No level and no Power Text here (no power bar).
    FB.PaintHealth = function(b, unitToken, cfg, full)
        local healthBar = b._health
        local pct = GetSafeHealthPercent(unitToken)
        healthBar:SetMinMaxValues(0, 100)
        local smooth = cfg.smoothBars
            and Enum
            and Enum.StatusBarInterpolation
            and Enum.StatusBarInterpolation.ExponentialEaseOut
        -- Missing health under Inverted Fill (the _cuiInv stamp FB.StyleVisuals leaves);
        -- the texts keep the current-health pct. Dead units are not special-cased: there
        -- is no status colour here, so a full bar is what tells a dead unit apart.
        local barPct = pct
        if healthBar._cuiInv then
            barPct = GetSafeHealthPercent(unitToken, true)
        end
        if smooth then
            healthBar:SetValue(barPct, smooth)
        else
            healthBar:SetValue(barPct)
        end

        local st = FB.txs[b]
        if not st then
            return
        end
        if full then
            mod.RF_TextFull(st, cfg, unitToken)
            return
        end
        local p = st._txP
        if p and (p.tick or p.custom) then
            mod.RF_TextHealth(
                st,
                unitToken,
                pct,
                UnitIsDeadOrGhost(unitToken) or not UnitIsConnected(unitToken),
                true
            )
        end
    end

    -- Refresh one boss button: health value/color, health text, name text, target state and border.
    -- Mirrors the corresponding slices of UpdateButton/_UpdateButtonHealth; boss units are not group
    -- units, so no roster paths. Returns true when it painted (border included); without a unit only a
    -- flipped target state repaints the border.
    FB.Update = function(b, ownerFrame)
        local unitToken = FB.UnitOf(b)
        local flipped = FB.ReadTarget(b, unitToken)
        if not saved or not UnitExists(unitToken) then
            if flipped then
                FB.ApplyBorderColor(b)
            end
            return
        end
        local s = FB.Source(b)
        FB.PaintBarColor(b, ownerFrame or FB, s)
        FB.PaintHealth(b, unitToken, s, true)
        FB.ApplyBorderColor(b)
        return true
    end

    -- Background, health bar, the texts and the border frame of one button, kept on the button itself
    -- with the stock styles' edge and highlight state. Shared with the pet frames, their preview and
    -- the party target frames. texts: the texts (FB.txs); without, the one name text the
    -- party target frames draw (they style it themselves). The pet header's buttons are made by the
    -- pet header, not by us: these keys on them are the one known exception to keeping state off
    -- header buttons (the rest lives in weak tables and GetFFD).
    FB.BuildVisuals = function(widget, texts)
        local backdrop = widget:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        if Pix then
            Pix.DisablePixelSnap(backdrop)
        end
        widget._bg = backdrop

        local healthBar = CreateFrame("StatusBar", nil, widget)
        healthBar:SetFrameLevel(widget:GetFrameLevel() + 2)
        healthBar:SetPoint("TOPLEFT", widget, "TOPLEFT", 0, 0)
        healthBar:SetPoint("TOPRIGHT", widget, "TOPRIGHT", 0, 0)
        if Pix then
            Pix.DisablePixelSnap(healthBar)
        end
        healthBar:SetMinMaxValues(0, 100)
        healthBar:SetValue(100)
        widget._health = healthBar

        local carrier = CreateFrame("Frame", nil, widget)
        carrier:SetAllPoints(healthBar)
        carrier:SetFrameLevel(widget:GetFrameLevel() + mod.LVL_TEXT)
        if texts then
            FB.txs[widget] = { textCarrier = carrier, _txHost = healthBar, _txFB = true }
        else
            local nameFS = carrier:CreateFontString(nil, "OVERLAY")
            nameFS:SetWordWrap(false)
            widget._nameText = nameFS
        end

        -- Border frame (same construction as the raid buttons; styled from the shared raid border settings in FB.StyleBorder)
        local bdr = CreateFrame("Frame", nil, widget)
        bdr:SetAllPoints(widget)
        bdr:SetFrameLevel(widget:GetFrameLevel() + 8)
        widget._borderFrame = bdr
        -- Stock styles: the stock edge and highlights.
        if mod.RF_Stock() then
            mod.RF_StockBuild(widget, widget)
        end
    end

    -- One-time construction of the container, the five buttons, click-cast registration and per-unit
    -- trackers. Buttons are created hidden; the secure visibility drivers own show/hide after that.
    FB.EnsureBuilt = function()
        if FB.built then
            return
        end
        FB.built = true

        local boxHolder = CreateFrame("Frame", "ERFFriendlyBossContainer", UIParent)
        boxHolder:Hide()
        FB.container = boxHolder

        for index = 1, 5 do
            local widget = CreateFrame("Button", "ERFFriendlyBoss" .. index, boxHolder, "SecureUnitButtonTemplate")
            widget._fbUnit = "boss" .. index
            widget:SetAttribute("unit", widget._fbUnit)
            widget:SetAttribute("*type1", "target")
            widget:RegisterForClicks("AnyUp")
            -- The engine gates SecureUnitButton's togglemenu; route right-click through a SecureActionButton proxy so the menu works without taint.
            if CludesUI.AttachSecureUnitMenu then
                CludesUI.AttachSecureUnitMenu(widget)
            else
                widget:SetAttribute("*type2", "togglemenu")
            end
            widget:Hide()
            FB.BuildVisuals(widget, true)

            -- Refresh as soon as the driver shows the button; visible-count drives the ticker lifecycle.
            widget:HookScript("OnShow", function(self)
                FB.visCount = (FB.visCount or 0) + 1
                -- Containers first: an error in the legacy refresh must not starve the unit assignment.
                if mod.RFC_OnUnitAssigned then
                    local skinData = GetFFD(self)
                    local unitToken = FB.UnitOf(self)
                    if skinData and unitToken then
                        mod.RFC_OnUnitAssigned(self, skinData, unitToken)
                    end
                end
                FB.Update(self)
                FB.ApplyRange(self)
                FB.UpdateRangeTicker()
            end)
            widget:HookScript("OnHide", function(self)
                FB.visCount = math.max(0, (FB.visCount or 0) - 1)
                FB.UpdateRangeTicker()
            end)

            -- Hover highlight (these are our own buttons; hooks are safe)
            widget:HookScript("OnEnter", function(self)
                FB.hov[self] = true
                FB.ApplyBorderColor(self)
            end)
            widget:HookScript("OnLeave", function(self)
                FB.hov[self] = nil
                FB.ApplyBorderColor(self)
            end)

            -- Re-render when the slot controller reassigns this slot's unit mid-combat (a boss
            -- spawning/despawning reflows the slots without an OnShow on already-visible buttons).
            widget:HookScript("OnAttributeChanged", function(self, label)
                if label == "unit" and self:IsVisible() then
                    -- Containers first (same rationale as the OnShow hook).
                    if mod.RFC_OnUnitAssigned then
                        local skinData = GetFFD(self)
                        local unitToken = FB.UnitOf(self)
                        if skinData and unitToken then
                            mod.RFC_OnUnitAssigned(self, skinData, unitToken)
                        end
                    end
                    FB.Update(self)
                    FB.ApplyRange(self)
                end
            end)

            -- Full click-cast / hovercast binding suite (mouseover heals included)
            if mod.CC_RegisterFrame then
                mod.CC_RegisterFrame(widget)
            end

            -- Boss units are outside the roster trackers; track here. The slot controller may have
            -- assigned this unit to ANY slot, so route the event to whichever button shows it.
            local unitId = "boss" .. index
            local t = mod.TakeShell()
            t:RegisterUnitEvent("UNIT_HEALTH", unitId)
            t:RegisterUnitEvent("UNIT_MAXHEALTH", unitId)
            t:RegisterUnitEvent("UNIT_NAME_UPDATE", unitId)
            t:SetScript("OnEvent", function()
                for _, button in ipairs(FB.buttons) do
                    if button:IsVisible() and button:GetAttribute("unit") == unitId then
                        FB.Update(button)
                        break
                    end
                end
            end)
            FB.trackers[index] = t

            FB.buttons[index] = widget

            if mod.RFC_SetupButton then
                local skinData = GetFFD(widget)
                mod.RFC_SetupButton(widget, widget._health, skinData)
            end
        end

        -- Slot controller: collapses friendly bosses into the FIRST slots (button positions fixed;
        -- units assigned in bossN order, buttons shown/hidden). Runs in the restricted environment so
        -- mid-combat spawns/despawns reflow safely (insecure code cannot Show/Hide or re-unit protected
        -- buttons in combat). Drivers registered in FB_Apply feed state-ingroup / state-fb1..5. One
        -- shared body per attribute; FB_Apply also force-runs it via SecureHandlerExecute because the
        -- driver manager skips the handler when a re-registered driver's value is unchanged.
        FB.RELAYOUT = [[
        local ingroup = self:GetAttribute("state-ingroup")
        local slot = 0
        if ingroup == 1 or ingroup == "1" then
            for i = 1, 5 do
                local v = self:GetAttribute("state-fb" .. i)
                if v == 1 or v == "1" then
                    slot = slot + 1
                    local b = self:GetFrameRef("slot" .. slot)
                    if b then
                        b:SetAttribute("unit", "boss" .. i)
                        b:Show()
                    end
                end
            end
        end
        for j = slot + 1, 5 do
            local b = self:GetFrameRef("slot" .. j)
            if b then b:Hide() end
        end
    ]]
        local controller =
            CreateFrame("Frame", "ERFFriendlyBossController", nil, "SecureHandlerAttributeTemplate")
        for index = 1, 5 do
            controller:SetFrameRef("slot" .. index, FB.buttons[index])
        end
        -- The template's handler attribute is "_onattributechanged" (wildcard receiving name/value).
        -- The relayout body lives in its own attribute so the handler and the force-run share it.
        controller:SetAttributeNoHandler("fb_relayout", FB.RELAYOUT)
        controller:SetAttributeNoHandler(
            "_onattributechanged",
            [[
        if name == "state-ingroup" or name == "state-fb1" or name == "state-fb2"
           or name == "state-fb3" or name == "state-fb4" or name == "state-fb5" then
            self:RunAttribute("fb_relayout")
        end
    ]]
        )
        FB.controller = controller
    end

    -- The pitch between the group's buttons. Attached beside Compact frames it takes their one
    -- pixel, so its rows stay level with theirs: the party frames' where FB.Anchor slots it in
    -- beside them (outside a raid, with Show in Dungeons on), else the raid groups'.
    FB.Pitch = function(fallbackSet, cfg)
        if fallbackSet and fallbackSet.position ~= "free" then
            local party = (not IsInRaid() or mod._PartyInRaid()) and fallbackSet.showInDungeons == true
            if mod.RF_CompactOn(saved.profile, party) then
                return mod.RF_OnePixel(party)
            end
        end
        -- Same grid as FB.FreePin: the boss container's own scale.
        local c = FB.container
        return CludesUI.PP.SnapForES(cfg.cellSpacing or -1, (c or UIParent):GetEffectiveScale())
    end

    -- Re-apply all setting-derived properties (size, slots, texture, fonts, text anchors). OOC only;
    -- callers gate. The owner parameter lets the Extra Frames duplicates (ns._XF) share this verbatim:
    -- an owner carries buttons/container/Settings and defaults to FB itself.
    FB.ApplyStyle = function(ownerFrame)
        ownerFrame = ownerFrame or FB
        if not ownerFrame.built then
            return
        end
        local cfg = mod._scaledProfile or saved.profile
        local fallbackSet = ownerFrame.Settings()
        -- Per-group size offset on the shared raid frame size (Extra Width/Height sliders; clamped so a negative offset can't invert a small frame).
        local wid = PixelSnap(math.max(10, (cfg.frameWidth or 125) + ((fallbackSet and fallbackSet.extraWidth) or 0)))
        local hgt = PixelSnap(math.max(10, (cfg.frameHeight or 60) + ((fallbackSet and fallbackSet.extraHeight) or 0)))
        local sp = FB.Pitch(fallbackSet, cfg)
        ownerFrame.pitch = sp
        -- Free Move ignores the raid growth settings: vertical stack by default, horizontal via the
        -- Horizontal Frames cog. Attached modes keep stacking like a real group (unitGrowth).
        local growDir
        if fallbackSet and fallbackSet.position == "free" then
            growDir = fallbackSet.freeHorizontal and "RIGHT" or "DOWN"
        else
            growDir = cfg.unitGrowth or "DOWN"
        end
        local texPath = ResolveHealthTexture()
        local bgc = cfg.customBgColor or { r = 17 / 255, g = 17 / 255, b = 17 / 255 }

        local stepW, stepH = 0, 0
        if growDir == "DOWN" or growDir == "UP" then
            ownerFrame.container:SetSize(wid, hgt * 5 + sp * 4)
            stepH = hgt + sp
        else
            ownerFrame.container:SetSize(wid * 5 + sp * 4, hgt)
            stepW = wid + sp
        end

        for index, btn in ipairs(ownerFrame.buttons) do
            btn:SetSize(wid, hgt)
            btn:ClearAllPoints()
            local off = index - 1
            if growDir == "UP" then
                btn:SetPoint("BOTTOMLEFT", ownerFrame.container, "BOTTOMLEFT", 0, off * stepH)
            elseif growDir == "LEFT" then
                btn:SetPoint("TOPRIGHT", ownerFrame.container, "TOPRIGHT", -off * stepW, 0)
            elseif growDir == "RIGHT" then
                btn:SetPoint("TOPLEFT", ownerFrame.container, "TOPLEFT", off * stepW, 0)
            else -- DOWN
                btn:SetPoint("TOPLEFT", ownerFrame.container, "TOPLEFT", 0, -off * stepH)
            end

            FB.StyleVisuals(btn, cfg, wid, hgt, texPath, bgc)
        end
    end

    -- The size-dependent part of FB.StyleVisuals (the health bar's height, the text widths): all a
    -- resize of an already styled button needs. s: the settings of a full restyle; a resize keeps the
    -- settings the texts were laid out with.
    FB.SizeVisuals = function(b, wid, hgt, s)
        -- No power bar / top name bar here: health fills the button.
        b._health:SetHeight(hgt)
        local st = FB.txs[b]
        if st then
            st._txW = wid
            if s or st._txL then
                mod.RF_TextLayout(st, s or st._txS)
            end
        end
    end

    -- Texture, fonts, text anchors and border of one button at w x h. Shared with the pet frames.
    FB.StyleVisuals = function(b, cfg, wid, hgt, texPath, bgc)
        mod.RF_TexBgTint(b._bg, mod.RF_TexBgPath(cfg), mod.RF_IsVerticalFill(cfg))
        b._bg:SetColorTexture(bgc.r, bgc.g, bgc.b, (cfg.bgDarkness or 50) / 100)
        b._health:SetStatusBarTexture(texPath)
        local ft = b._health:GetStatusBarTexture()
        if ft then
            ft:SetHorizTile(false)
        end
        -- Fill axis follows the raid Health Bar setting. The bg is a full-button texture (not fill-tracking), so nothing else re-anchors.
        mod.RF_ApplyHealthOrientation(b._health, cfg)
        -- These carry aura containers (RFC_SetupButton below) and so can carry
        -- Health Bar Color overlays, but they have no absorb cluster and never
        -- build ReanchorAbsorbToFill, where every other frame picks the swap up.
        b._health._cuiFillOpacity = (cfg.healthBarOpacity or 100) / 100
        mod.RF_RefreshBarTints(b._health)
        FB.SizeVisuals(b, wid, hgt, cfg)
        FB.StyleBorder(b)
    end

    -- A container's one anchor point, left alone when it already sits exactly there: the roster and
    -- layout passes re-anchor with unchanged targets, and rewriting a protected frame's point re-lays
    -- it and every button under it. A secret point always rewrites.
    FB.Pin = function(c, anchorPoint, rel, relPoint, posX, posY)
        if c:GetNumPoints() == 1 then
            local p, region, rp, px, py = c:GetPoint(1)
            if
                not (
                    issecretvalue(p)
                    or issecretvalue(region)
                    or issecretvalue(rp)
                    or issecretvalue(px)
                    or issecretvalue(py)
                )
                and p == anchorPoint
                and region == rel
                and rp == relPoint
                and px == posX
                and py == posY
            then
                return
            end
        end
        c:ClearAllPoints()
        c:SetPoint(anchorPoint, rel, relPoint, posX, posY)
    end

    -- Free Move pin off UIParent's centre. The saved offsets are raw mover geometry and the centre
    -- itself can sit on a half pixel (odd physical size), so snap the pinned point's absolute
    -- position at the container's own scale, or every border inside it blurs. A CENTER pin snaps
    -- with the container's size so odd-pixel dimensions still put both edges on whole pixels.
    FB.FreePin = function(c, anchorPoint, posX, posY)
        local P = CludesUI.PP
        local unitX, unitY = UIParent:GetCenter()
        if unitX then
            local es = c:GetEffectiveScale()
            if anchorPoint == "CENTER" then
                -- A secret size falls back to the even (whole-pixel) centre.
                local wid, hgt = c:GetWidth(), c:GetHeight()
                if issecretvalue(wid) then
                    wid = nil
                end
                if issecretvalue(hgt) then
                    hgt = nil
                end
                posX = P.SnapCenterForDim(unitX + posX, wid, es) - unitX
                posY = P.SnapCenterForDim(unitY + posY, hgt, es) - unitY
            else
                posX = P.SnapForES(unitX + posX, es) - unitX
                posY = P.SnapForES(unitY + posY, es) - unitY
            end
        end
        FB.Pin(c, anchorPoint, UIParent, "CENTER", posX, posY)
    end

    -- Position the container per the position setting. The container inherits protection from its
    -- secure children, so SetPoint is OOC-only. Owner-parameterized like ApplyStyle. Every placement
    -- goes through FB.Pin (owner.FreeAnchor included).
    FB.Anchor = function(ownerFrame)
        ownerFrame = ownerFrame or FB
        if not ownerFrame.built then
            return
        end
        if InCombatLockdown() then
            ownerFrame.anchorDirty = true
            return
        end
        local cfg = saved.profile
        local fallback = ownerFrame.Settings()
        local c = ownerFrame.container
        -- A group's pitch follows the frames it sits beside (owner.Pitch: the boss group, the
        -- Extra Frames): re-lay it once that moved.
        if ownerFrame.Pitch and ownerFrame.pitch ~= ownerFrame.Pitch(fallback, mod._scaledProfile or cfg) then
            if ownerFrame.Layout then
                ownerFrame.Layout()
            else
                FB.ApplyStyle(ownerFrame)
            end
        end

        if fallback.position ~= "free" then
            local anchorHeader
            -- Chain rule: when the boss group (owner == FB) and Extra Frames attach to the SAME side,
            -- the boss group anchors to the extra container instead of the raid -- order raid -> extra
            -- -> boss (mirrored on "left"). Extra Frames always anchor to the raid; ns.XF_Apply re-runs
            -- this anchor when that container shows/hides/moves.
            if ownerFrame == FB then
                local xf = mod._XF
                local xs = xf and xf.Settings and xf.Settings()
                if
                    xs
                    and xs.position == fallback.position
                    and xf.built
                    and xf.container
                    and xf.container:IsShown()
                then
                    anchorHeader = xf.container
                end
            end
            -- Owners placed after other attached groups on the same side (the pet frames), which
            -- remember the group they followed (owner.chainTgt).
            if not anchorHeader and ownerFrame.ChainAnchor then
                anchorHeader = ownerFrame.ChainAnchor(fallback)
                ownerFrame.chainTgt = anchorHeader or false
                -- Beside the party frames the chain runs on the party attach axis, not the raid growth,
                -- with the same kit side and clearance, and the corner the party stack grows from.
                if anchorHeader and ownerFrame.attachParty then
                    local spacing = cfg.groupSpacing or -1
                    local before = (fallback.position == "left")
                    if mod.RF_PartyKit() then
                        local extra
                        before, extra = mod.RF_KitAttach(cfg, before)
                        spacing = spacing + extra
                    end
                    local growDir = mod._PartyGrowth(cfg)
                    if growDir == "UP" then
                        if before then
                            FB.Pin(c, "BOTTOMRIGHT", anchorHeader, "BOTTOMLEFT", -spacing, 0)
                        else
                            FB.Pin(c, "BOTTOMLEFT", anchorHeader, "BOTTOMRIGHT", spacing, 0)
                        end
                    elseif growDir == "LEFT" then
                        if before then
                            FB.Pin(c, "BOTTOMRIGHT", anchorHeader, "TOPRIGHT", 0, spacing)
                        else
                            FB.Pin(c, "TOPRIGHT", anchorHeader, "BOTTOMRIGHT", 0, -spacing)
                        end
                    elseif cfg.partyHorizontal then
                        if before then
                            FB.Pin(c, "BOTTOMLEFT", anchorHeader, "TOPLEFT", 0, spacing)
                        else
                            FB.Pin(c, "TOPLEFT", anchorHeader, "BOTTOMLEFT", 0, -spacing)
                        end
                    else
                        if before then
                            FB.Pin(c, "TOPRIGHT", anchorHeader, "TOPLEFT", -spacing, 0)
                        else
                            FB.Pin(c, "TOPLEFT", anchorHeader, "TOPRIGHT", spacing, 0)
                        end
                    end
                    return
                end
            end
            -- Party/dungeon: every raid group header is hidden there, so the boss group slots in beside
            -- the party container as if it were the next group -- along the axis the party frames do NOT
            -- stack on, the way "before first / after last group" reads in a raid. Extra Frames is raid
            -- only and keeps the raid path. Party frames off screen leaves nothing to attach to: this
            -- branch anchors nothing and the free position below takes over.
            if
                not anchorHeader
                and (not IsInRaid() or mod._PartyInRaid())
                and ((ownerFrame == FB and fallback.showInDungeons == true) or ownerFrame.attachParty)
            then
                local pc = mod._partyContainerFrame
                if pc and pc:IsShown() then
                    local spacing = cfg.groupSpacing or -1
                    local before = (fallback.position == "left")
                    -- Party Frames kit: clear the auras it draws outside the frames.
                    if mod.RF_PartyKit() then
                        local extra
                        before, extra = mod.RF_KitAttach(cfg, before)
                        spacing = spacing + extra
                    end
                    -- The group clears the party target frames on its side, and the boss group the
                    -- Beside Owner pets there too (the pet header is down while those are up).
                    spacing = spacing
                        + mod.PT_Reserve(
                            cfg.partyHorizontal,
                            before,
                            (ownerFrame == FB) and mod.PF_OwnerReserve(cfg.partyHorizontal, before) or nil
                        )
                    -- Pets line up with the first party frame: Flip Frame Growth and Centered start
                    -- the stack away from the container's top-left.
                    if ownerFrame ~= FB then
                        local first = mod._partyFirstSlot or pc
                        local growDir = mod._PartyGrowth(cfg)
                        if growDir == "UP" then
                            if before then
                                FB.Pin(c, "BOTTOMRIGHT", first, "BOTTOMLEFT", -spacing, 0)
                            else
                                FB.Pin(c, "BOTTOMLEFT", first, "BOTTOMRIGHT", spacing, 0)
                            end
                            return
                        elseif growDir == "LEFT" then
                            if before then
                                FB.Pin(c, "BOTTOMRIGHT", first, "TOPRIGHT", 0, spacing)
                            else
                                FB.Pin(c, "TOPRIGHT", first, "BOTTOMRIGHT", 0, -spacing)
                            end
                            return
                        end
                        pc = first
                    end
                    -- Party growth axis comes from partyHorizontal alone (_LayoutPartyFrames): the flip
                    -- and "centered" variants only reverse it, and the container spans all five slots
                    -- either way, so the perpendicular attach point is the same.
                    if cfg.partyHorizontal then
                        if before then
                            FB.Pin(c, "BOTTOMLEFT", pc, "TOPLEFT", 0, spacing)
                        else
                            FB.Pin(c, "TOPLEFT", pc, "BOTTOMLEFT", 0, -spacing)
                        end
                    else
                        if before then
                            FB.Pin(c, "TOPRIGHT", pc, "TOPLEFT", -spacing, 0)
                        else
                            FB.Pin(c, "TOPLEFT", pc, "TOPRIGHT", spacing, 0)
                        end
                    end
                    return
                end
            elseif not anchorHeader and cfg.mergeGroups then
                anchorHeader = mod._flatHeader
            elseif not anchorHeader then
                -- The boss group slots in before the first / after the last group that is BOTH enabled
                -- in Show Groups AND populated. With none populated (not in a raid yet), fall back to
                -- the Show Groups bounds alone.
                local vg = mod._VisibleGroups() or {}
                -- One reused set across calls (the roster edges anchor every group).
                local occupied = FB.occ
                if occupied then
                    wipe(occupied)
                else
                    occupied = {}
                    FB.occ = occupied
                end
                for ri = 1, GetNumGroupMembers() or 0 do
                    local _, _, sub = GetRaidRosterInfo(ri)
                    if sub then
                        occupied[sub] = true
                    end
                end
                local first, last
                local groupOrder = cfg.customGroupOrder and mod._RFValidatedGroupOrder(cfg.groupOrder)
                for slotIndex = 1, 8 do
                    local growInfo = groupOrder and groupOrder[slotIndex] or slotIndex
                    if vg[growInfo] ~= false and separatedHdrs[growInfo] and occupied[growInfo] then
                        if not first then
                            first = separatedHdrs[growInfo]
                        end
                        last = separatedHdrs[growInfo]
                    end
                end
                if not first then
                    for slotIndex = 1, 8 do
                        local growInfo = groupOrder and groupOrder[slotIndex] or slotIndex
                        if vg[growInfo] ~= false and separatedHdrs[growInfo] then
                            if not first then
                                first = separatedHdrs[growInfo]
                            end
                            last = separatedHdrs[growInfo]
                        end
                    end
                end
                anchorHeader = (fallback.position == "left") and first or last
            end
            if anchorHeader then
                -- Slot in along the group growth axis exactly like a real group.
                local spacing = cfg.groupSpacing or -1
                local growDir = cfg.groupGrowth or "RIGHT"
                local before = (fallback.position == "left")
                if growDir == "RIGHT" or growDir == "DOWNRIGHT" then
                    -- The grid flow's last group also ends in the rightmost column,
                    -- so it slots in along the same edge as a plain RIGHT run.
                    if before then
                        FB.Pin(c, "TOPRIGHT", anchorHeader, "TOPLEFT", -spacing, 0)
                    else
                        FB.Pin(c, "TOPLEFT", anchorHeader, "TOPRIGHT", spacing, 0)
                    end
                elseif growDir == "LEFT" then
                    if before then
                        FB.Pin(c, "TOPLEFT", anchorHeader, "TOPRIGHT", spacing, 0)
                    else
                        FB.Pin(c, "TOPRIGHT", anchorHeader, "TOPLEFT", -spacing, 0)
                    end
                elseif growDir == "DOWN" then
                    if before then
                        FB.Pin(c, "BOTTOMLEFT", anchorHeader, "TOPLEFT", 0, spacing)
                    else
                        FB.Pin(c, "TOPLEFT", anchorHeader, "BOTTOMLEFT", 0, -spacing)
                    end
                else -- UP
                    if before then
                        FB.Pin(c, "TOPLEFT", anchorHeader, "BOTTOMLEFT", 0, -spacing)
                    else
                        FB.Pin(c, "BOTTOMLEFT", anchorHeader, "TOPLEFT", 0, spacing)
                    end
                end
                return
            end
            -- No usable group header: fall through to the free position.
        end

        -- Owner-specific free anchoring (Extra Frames pins the grid's growth corner so the group grows away from it); CENTER pin otherwise.
        if ownerFrame.FreeAnchor and ownerFrame.FreeAnchor(c, fallback) then
            return
        end
        local p = fallback.freePos or {}
        FB.FreePin(c, "CENTER", p.x or 100, p.y or 0)
    end

    -- Re-anchor only (no restyle): the party visibility pass calls this on the party container's
    -- show/hide edge, since attached positions hang off that container outside a raid. Gated on
    -- the Show in Dungeons opt-in: with it off the party attach branch is inert, so the party
    -- layout/visibility hooks skip the re-anchor entirely (zero added work for raid-only users).
    function mod.FB_ReAnchor()
        mod.PF_PartyRelayout()
        if not FB.built then
            return
        end
        local fallback = FB.Settings and FB.Settings()
        if fallback and fallback.showInDungeons == true then
            FB.Anchor()
        end
    end

    -- Master apply: activates, deactivates and refreshes the whole feature. Called from OnEnable, the
    -- options dropdowns, spec changes, profile swaps (_CURF_RefreshAll) and the post-combat dirty pass.
    function mod.FB_Apply()
        if not saved or not saved.profile then
            return
        end
        local fallback = FB.Settings()
        if not fallback then
            return
        end
        if InCombatLockdown() then
            FB.applyDirty = true
            return
        end

        if not FB.ShouldBeActive() then
            if FB.built then
                if FB.controller then
                    UnregisterAttributeDriver(FB.controller, "state-ingroup")
                    for index = 1, 5 do
                        UnregisterAttributeDriver(FB.controller, "state-fb" .. index)
                    end
                end
                for _, btn in ipairs(FB.buttons) do
                    btn:Hide()
                end
                FB.container:Hide()
            end
            if FB.mover then
                FB.mover:Hide()
            end
            FB.rangeSpell = nil
            FB.UpdateRangeTicker()
            FB.SyncGroupEvents(false)
            return
        end

        FB.EnsureBuilt()
        FB.ApplyStyle()
        FB.Anchor()
        FB.container:Show()
        FB.SyncGroupEvents(true)
        -- Drivers feed the slot controller, which assigns bosses to the first slots in bossN order and shows/hides buttons securely.
        -- Group gate: raid only by default; raid OR party with Show in Dungeons on (the cog on
        -- Add Friendly Boss Group -- opt-in, so existing users keep raid-only behavior). Dungeon
        -- encounters expose the same healable bossN tokens. The toggle's setter re-runs FB_Apply,
        -- so re-registering here applies the flip live in either direction.
        local groupCond = (fallback.showInDungeons == true) and "[@raid1,exists][@party1,exists] 1; 0"
            or "[@raid1,exists] 1; 0"
        RegisterAttributeDriver(FB.controller, "state-ingroup", groupCond)
        for index = 1, 5 do
            RegisterAttributeDriver(FB.controller, "state-fb" .. index, "[@boss" .. index .. ",help] 1; 0")
        end
        -- Force one relayout now: the driver manager fires attribute handlers only on VALUE CHANGES, so
        -- a (re)apply with unchanged states would never run the initial layout. FB_Apply is OOC-only,
        -- so the insecure Execute is always legal here.
        if SecureHandlerExecute then
            SecureHandlerExecute(FB.controller, FB.RELAYOUT)
        end
        for _, btn in ipairs(FB.buttons) do
            if btn:IsVisible() then
                FB.Update(btn)
            end
        end

        -- Range dimming: healer specs only (regardless of display mode).
        local specInfo = GetSpecialization and GetSpecialization()
        local role = specInfo and GetSpecializationRole and GetSpecializationRole(specInfo)
        local _, pClass = UnitClass("player")
        FB.rangeSpell = (role == "HEALER") and FB.RANGE_HEAL[pClass] or nil
        -- WoW Forever: a healing class range-checks with its best known heal.
        if CludesUI.IS_FOREVER then
            FB.rangeSpell = FB.ForeverKnownHeal(pClass)
        end
        if not FB.rangeSpell then
            for _, btn in ipairs(FB.buttons) do
                btn:SetAlpha(1)
            end
        else
            for _, btn in ipairs(FB.buttons) do
                if btn:IsVisible() then
                    FB.ApplyRange(btn)
                end
            end
        end
        FB.UpdateRangeTicker()
    end

    -- A new pixel grid: the anchor pass re-lays each shown attached group whose one-pixel
    -- pitch moved (the Extra Frames first: a boss group may be chained behind them).
    function mod.FB_Repitch()
        local xf = mod._XF
        if xf and xf.built and xf.container:IsShown() then
            FB.Anchor(xf)
        end
        if FB.built and FB.container:IsShown() then
            FB.Anchor()
        end
    end

    function mod.FB_IsMoverShown()
        return FB.mover and FB.mover:IsShown() or false
    end

    -- Free Move corner pin (Extra Frames, Pet Frames): the corner a grid grows from (hDir, vDir: its
    -- horizontal and vertical growth), so its first frame stays put as frames come and go, and with a
    -- saved rect r (FB.SaveMoverRect) that corner's offset from UIParent's centre.
    FB.CornerPin = function(hDir, vDir, region)
        local corner
        if vDir == "UP" then
            corner = (hDir == "LEFT") and "BOTTOMRIGHT" or "BOTTOMLEFT"
        else
            corner = (hDir == "LEFT") and "TOPRIGHT" or "TOPLEFT"
        end
        if not region then
            return corner
        end
        return corner, (hDir == "LEFT") and region.right or region.left, (vDir == "UP") and region.bottom or region.top
    end

    -- The shared mover's drag stop, for corner-pinned owners: the dropped rect, relative to UIParent's
    -- centre, into set.freeRect.
    FB.SaveMoverRect = function(mover, set)
        if not set then
            return
        end
        local unitX, unitY = UIParent:GetCenter()
        local l, b, mw, mh = mover:GetRect()
        if not (unitX and l) then
            return
        end
        set.freeRect = { left = l - unitX, right = l + mw - unitX, bottom = b - unitY, top = b + mh - unitY }
    end

    -- Free Move drag overlay (unlock-mode look, TOOLTIP strata so it floats above the options panel).
    -- Deliberately independent of unlock mode. Owner-parameterized: the Extra Frames and pet groups
    -- build their own movers through this exact code with their own name/label (stored at owner.mover).
    FB.SetMoverShown = function(ownerFrame, show, frameName, labelText)
        if not show then
            if ownerFrame.mover then
                ownerFrame.mover:Hide()
            end
            return
        end
        -- Owners whose overlay can place another context's spot (the pet frames' Party and Raid tabs)
        -- read the overlay's settings, and bring their live group up to date themselves.
        local moverSettings = ownerFrame.MoverSettings or ownerFrame.Settings
        local fallback = moverSettings()
        if not fallback or fallback.position ~= "free" then
            return
        end
        if ownerFrame.MoverPrep then
            ownerFrame.MoverPrep()
        else
            ownerFrame.EnsureBuilt()
            -- Owners with their own geometry pass (Extra Frames) restyle through it; FB-built buttons use the FB styler.
            if ownerFrame.Layout then
                ownerFrame.Layout()
            else
                FB.ApplyStyle(ownerFrame)
            end
            FB.Anchor(ownerFrame)
        end

        if not ownerFrame.mover then
            local m = CreateFrame("Frame", frameName, UIParent)
            m:SetFrameStrata("TOOLTIP")
            m:SetClampedToScreen(true)
            m:SetMovable(true)
            m:EnableMouse(true)
            m:RegisterForDrag("LeftButton")
            local mbg = m:CreateTexture(nil, "BACKGROUND")
            mbg:SetAllPoints()
            mbg:SetColorTexture(0.088, 0.098, 0.111, 0.95)
            local ar, ag, ab = CludesUI.ResolveActiveAccent()
            CludesUI.MakeBorder(m, ar or 1, ag or 1, ab or 1, 0.6)
            local labelFS = m:CreateFontString(nil, "OVERLAY")
            CludesUI.PrimeFontShadow(labelFS, true)
            labelFS:SetFont(CludesUI.GetFontPath("raidFrames"), 11, "")
            labelFS:SetTextColor(1, 1, 1, 0.75)
            labelFS:SetPoint("CENTER", m, "CENTER")
            labelFS:SetWordWrap(false)
            labelFS:SetText(CludesUI.L(labelText))
            m:SetScript("OnDragStart", function(self)
                self:StartMoving()
            end)
            m:SetScript("OnDragStop", function(self)
                self:StopMovingOrSizing()
                local cx, cy = self:GetCenter()
                local unitX, unitY = UIParent:GetCenter()
                if cx and unitX then
                    local set = (ownerFrame.MoverSettings or ownerFrame.Settings)()
                    if set then
                        set.freePos = {
                            x = math.floor(cx - unitX + 0.5),
                            y = math.floor(cy - unitY + 0.5),
                        }
                    end
                end
                -- Corner-pinned owners also capture the dropped rect
                if ownerFrame.SaveFreeRect then
                    ownerFrame.SaveFreeRect(self)
                end
                FB.Anchor(ownerFrame)
            end)
            ownerFrame.mover = m
            -- Close the mover with the options panel so it can't be stranded.
            if CludesUI._mainFrame then
                CludesUI._mainFrame:HookScript("OnHide", function()
                    m:Hide()
                end)
            end
        end

        ownerFrame.mover:ClearAllPoints()
        local oset = moverSettings() or {}
        if ownerFrame.PlaceMover then
            ownerFrame.PlaceMover(ownerFrame.mover, oset)
        else
            ownerFrame.mover:SetSize(ownerFrame.container:GetWidth(), ownerFrame.container:GetHeight())
            if ownerFrame.FreeAnchor and oset.freeRect then
                -- Corner-pinned owners: mirror the container's placement so the overlay always covers the live grid (FB.Anchor just ran).
                ownerFrame.mover:SetPoint("CENTER", ownerFrame.container, "CENTER")
            else
                local p = oset.freePos or {}
                FB.FreePin(ownerFrame.mover, "CENTER", p.x or 100, p.y or 0)
            end
        end
        ownerFrame.mover:Show()
    end

    function mod.FB_SetMoverShown(show)
        FB.SetMoverShown(FB, show, "ERFFriendlyBossMover", "Friendly Boss Frames")
    end

    -- Standing event frame: exists even while inactive so a spec change can activate display="healers" without a /reload.
    -- The engage, target and roster listeners run only while the group is up (FB.SyncGroupEvents, from FB_Apply).
    do
        local eventName = mod.TakeShell()
        eventName:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        eventName:RegisterEvent("PLAYER_REGEN_ENABLED")
        eventName:RegisterEvent("PLAYER_ENTERING_WORLD")
        FB.SyncGroupEvents = function(enabled)
            if FB.groupEv == enabled then
                return
            end
            FB.groupEv = enabled
            if enabled then
                eventName:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
                eventName:RegisterEvent("GROUP_ROSTER_UPDATE")
                eventName:RegisterEvent("PLAYER_TARGET_CHANGED")
            else
                eventName:UnregisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
                eventName:UnregisterEvent("GROUP_ROSTER_UPDATE")
                eventName:UnregisterEvent("PLAYER_TARGET_CHANGED")
            end
        end
        eventName:SetScript("OnEvent", function(_, evt)
            if not saved then
                return
            end
            if evt == "PLAYER_SPECIALIZATION_CHANGED" then
                mod.FB_Apply()
            elseif evt == "PLAYER_ENTERING_WORLD" then
                -- Entering or leaving an arena flips FB.ShouldBeActive; the raid frames' zone-in pass
                -- re-applies only while they are on screen, which they never are in arena.
                local arena = mod._InArena()
                if arena ~= (FB.inArena == true) then
                    FB.inArena = arena
                    mod.FB_Apply()
                end
            elseif evt == "PLAYER_REGEN_ENABLED" then
                if FB.applyDirty then
                    FB.applyDirty = nil
                    mod.FB_Apply()
                end
                if FB.anchorDirty then
                    FB.anchorDirty = nil
                    FB.Anchor()
                end
            elseif not FB.built or not FB.container or not FB.container:IsShown() then
                return
            elseif evt == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
                for _, btn in ipairs(FB.buttons) do
                    if btn:IsVisible() then
                        FB.Update(btn)
                    end
                end
            elseif evt == "PLAYER_TARGET_CHANGED" then
                -- Only the border state can change here, and only on the buttons that flipped
                for _, btn in ipairs(FB.buttons) do
                    if btn:IsVisible() and FB.ReadTarget(btn, FB.UnitOf(btn)) then
                        FB.ApplyBorderColor(btn)
                    end
                end
            elseif evt == "GROUP_ROSTER_UPDATE" then
                -- First/last visible group (and the size tier) can shift with
                -- the roster; restyle + re-anchor, deferred through combat.
                if InCombatLockdown() then
                    FB.applyDirty = true
                else
                    FB.ApplyStyle()
                    FB.Anchor()
                end
            end
        end)
        FB.eventFrame = eventName
    end
end -- FB scope block

Inner.broken = false
