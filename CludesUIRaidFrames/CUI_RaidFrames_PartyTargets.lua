if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_RaidFrames_PartyTargets.lua
--
--  Party Targets: a secure target button beside each party frame.
--  Reads the earlier Raid Frames files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIRaidFrames.lua or an earlier Raid Frames file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local max = math.max
local ipairs = ipairs
local wipe = wipe
local UnitName = UnitName
local UnitClass = UnitClass
local UnitExists = UnitExists
local IsInRaid = IsInRaid
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local issecretvalue = issecretvalue
local CreateFrame = CreateFrame

local ApplyFont, PixelSnap = Inner.ApplyFont, Inner.PixelSnap
local ResolveHealthTexture = Inner.ResolveHealthTexture
local GetClassicHealthCurve = Inner.GetClassicHealthCurve
local GetSafeHealthPercent = Inner.GetSafeHealthPercent

local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(val)
    saved = val
end

-------------------------------------------------------------------------------
-- Party Targets (opt-in, Party-only)
--
-- Secure buttons attached to party-header children and (Include Own Target
-- with Show Self First / Last) the self button. Their unit resolves as the
-- owner's current target at click time, so no protected unit mutation is
-- needed in combat.
-- Placement: the Position setting (unset: beside stacked frames, below
-- horizontal ones) plus its offsets. Across the stack (left/right of stacked
-- frames, above/below horizontal ones) the frames move off the Party Frames
-- kit's outside auras and follow the Beside Owner pets on that side, as the
-- pets do, and the groups attached beside the party frames (Friendly Boss,
-- the pet header) reserve the reach through ns.PT_Reserve. Along the stack
-- the chosen side is kept exactly and the party frames' pitch opens by the
-- frames' room (ns.PT_AlongPitch), so they sit between two party frames.
-- Look: a health bar on the Friendly Boss visuals (the stock edge under a
-- stock style) with the party texture, name font and border, and their own
-- Fill Color and Background.
-- Updates: a party member's target has no unit events, so one hidden 0.5 s
-- ticker reads the values while such a frame shows, and re-checks a mob's
-- tap and reaction (its colour); your own target is evented. Names and
-- colours otherwise repaint on target changes, unit re-assignments, roster
-- edges and settings pushes only.
-------------------------------------------------------------------------------
mod._partyTargetFrames = mod._partyTargetFrames or {}
mod._ptEnabled = false
mod._ptDesired = false
mod._ptInclDesired = false

do
    local CUI = mod.CludesUI
    -- Layout state (the last applied size, side, gaps and offsets: the layout's delta gate and the
    -- reserve's source), the colour settings the paint reads (cached by the restyle), the listeners,
    -- and the owner bookkeeping: owner token -> "<token>target", header button -> its target frame.
    local PT = {
        tgtOf = {},
        frameOf = setmetatable({}, { __mode = "k" }),
        tgtEv = {},
        tgtWant = {},
        acc = 0,
        DEF_FILL = { r = 37 / 255, g = 193 / 255, b = 29 / 255 },
    }
    -- The shared style inputs plus the target frames' own ten (PT_FpExtra).
    PT.FP_N = mod._PF.STYLE_N + 10

    -- Owner unit -> its target frame, for UNIT_TARGET. Frames showing your own target stay out: they
    -- read "target" and follow PLAYER_TARGET_CHANGED.
    local PT_BY_UNIT = {}

    -- The settings the target frames are styled from: the party ones, as the Beside Owner pets.
    local function PT_Source()
        return mod._scaledPartyProxy
    end

    -- "party1" -> "party1target", built once per token.
    local function PT_TargetOf(u)
        local t = PT.tgtOf[u]
        if not t then
            t = u .. "target"
            PT.tgtOf[u] = t
        end
        return t
    end

    -- Your raid token while the party frames run on raid units (arena, Small Raid), else nil.
    local function PT_Me()
        if not IsInRaid() then
            return nil
        end
        local index = UnitInRaid("player")
        if issecretvalue(index) or not index then
            return nil
        end
        return "raid" .. index
    end

    -- The unit a frame reads, from its owner's current unit: your own target reads "target" (the token
    -- your target's events carry), anyone else's "<owner>target". Keeps PT_BY_UNIT current. Returns
    -- true when the frame's owner changed.
    local function PT_Classify(widget)
        local ou, own
        if widget == PT.selfFrame then
            own = true
        else
            ou = widget._ptOwner:GetAttribute("unit")
            own = ou ~= nil and (ou == "player" or ou == PT.me)
        end
        local key = (not own) and ou or nil
        local old = widget._ptOwnerUnit
        local changed = old ~= key or widget._ptOwn ~= own
        if old ~= key then
            if old and PT_BY_UNIT[old] == widget then
                PT_BY_UNIT[old] = nil
            end
            if key then
                PT_BY_UNIT[key] = widget
            end
            widget._ptOwnerUnit = key
        end
        widget._ptOwn = own
        widget._ptUnit = (own and "target") or (ou and PT_TargetOf(ou)) or nil
        return changed
    end

    -- Class colour for players and party AI (the custom one where a restricted token still allows it),
    -- grey for a tapped mob, the reaction colour for other NPCs. Returns ok, r, g, b; r/g/b may be
    -- SECRET on the restricted path: only ever handed to a setter, never compared. A mob's tap and
    -- reaction (neither secret) are kept on frame, for the ticker's re-check.
    local function PT_ClassRGB(u, widget)
        if UnitIsPlayer(u) or (UnitInPartyIsAI and UnitInPartyIsAI(u)) then
            local _, ct = UnitClass(u)
            if issecretvalue(ct) then
                local success, region, g, b = CUI.GetClassColorForRestrictedUnit(u, ct)
                if success then
                    return true, region, g, b
                end
                local c = C_ClassColor.GetClassColor(ct)
                if c then
                    return true, c.r, c.g, c.b
                end
                return false
            end
            local cc = ct and CUI.GetClassColor(ct)
            if cc then
                return true, cc.r, cc.g, cc.b
            end
            return false
        end
        local tap = UnitIsTapDenied(u)
        local re = UnitReaction(u, "player")
        if issecretvalue(re) then
            re = nil
        end
        if widget then
            widget._ptNpc, widget._ptTap, widget._ptRe = true, tap, re
        end
        if tap then
            return true, 0.6, 0.6, 0.6
        end
        local c = re and FACTION_BAR_COLORS[re]
        if c then
            return true, c.r, c.g, c.b
        end
        return false
    end

    -- The Classic gradient at the unit's current health (the engine evaluates the curve, secret-safe).
    local function PT_PaintClassic(health, u)
        local c = UnitHealthPercent(u, true, GetClassicHealthCurve())
        if c and c.GetRGB then
            health:SetStatusBarColor(c:GetRGB())
        end
    end

    -- Identity paint: name, fill and background colours, and the value, which jumps (a new unit). Runs
    -- on target, unit and settings edges only. Names and colours can be secret: setters only.
    local function PT_Paint(widget)
        local u = widget._ptUnit
        -- Set again below only for a mob whose colour reads its tap and reaction.
        widget._ptNpc = nil
        if not (u and UnitExists(u)) then
            return
        end
        widget._nameText:SetText(UnitName(u))
        local health, backdrop, mode = widget._health, widget._bg, PT.mode
        local fillTex = health:GetStatusBarTexture()
        if mode == "dark" then
            local region, g, b, a = CUI.GetDarkModeFill()
            health:SetStatusBarColor(region, g, b, 1)
            if fillTex then
                fillTex:SetAlpha(a)
            end
            backdrop:SetColorTexture(CUI.GetDarkModeBg())
        else
            if fillTex then
                fillTex:SetAlpha(1)
            end
            local success, region, g, b = false
            if (mode ~= "classic" and mode ~= "custom") or PT.bgClass then
                success, region, g, b = PT_ClassRGB(u, widget)
            end
            if mode == "classic" then
                PT_PaintClassic(health, u)
            elseif mode == "custom" then
                health:SetStatusBarColor(PT.fr, PT.fg, PT.fb, 1)
            elseif success then
                health:SetStatusBarColor(region, g, b, 1)
            else
                health:SetStatusBarColor(0.5, 0.5, 0.5, 1)
            end
            if success and PT.bgClass then
                backdrop:SetColorTexture(region, g, b, PT.bgA)
            else
                backdrop:SetColorTexture(PT.br, PT.bgg, PT.bb, PT.bgA)
            end
        end
        health:SetValue(GetSafeHealthPercent(u))
    end

    -- Value paint (the ticker and your target's health events), smoothed per Smooth Bars; the Classic
    -- gradient follows the value.
    local function PT_PaintValue(widget, u)
        local health = widget._health
        local smooth = PT.smooth
        if smooth then
            health:SetValue(GetSafeHealthPercent(u), smooth)
        else
            health:SetValue(GetSafeHealthPercent(u))
        end
        if PT.mode == "classic" then
            PT_PaintClassic(health, u)
        end
    end

    -- Every target frame on screen, in full (settings pushes: a restyle, Dark Mode and class colours
    -- through ERF:UpdateAllFrames, roster edges). Nothing while off.
    mod._PT_RepaintVisible = function()
        if not mod._ptEnabled then
            return
        end
        for _, widget in ipairs(mod._partyTargetFrames) do
            if widget:IsVisible() then
                PT_Paint(widget)
            end
        end
    end

    -- The frames on screen drive every per-unit listener. Polled frames (a party member's target):
    -- UNIT_TARGET on their owners' units only (listener k covers frames 2k-1 and 2k, so a frame
    -- showing or hiding re-registers its own listener alone; a target appearing shows its frame
    -- through the unit watch), and the ticker while one shows. Own frames (your target): your target's
    -- events while one shows with Include Own Target on. Nameplates and every other unit stay out.
    -- except: a frame on its way off screen.
    local function PT_Recount(except)
        local wanted, poll, own = PT.tgtWant, 0, 0
        wipe(wanted)
        if mod._ptEnabled then
            for i, frame in ipairs(mod._partyTargetFrames) do
                if frame ~= except and frame:IsVisible() then
                    if frame._ptOwn then
                        own = own + 1
                    elseif frame._ptOwnerUnit then
                        poll = poll + 1
                        wanted[i] = frame._ptOwnerUnit
                    end
                end
            end
        end
        for k = 1, #PT.tgtEv do
            local ev = PT.tgtEv[k]
            local u1, u2 = wanted[2 * k - 1], wanted[2 * k]
            if ev.ptU1 ~= u1 or ev.ptU2 ~= u2 then
                ev.ptU1, ev.ptU2 = u1, u2
                ev:UnregisterEvent("UNIT_TARGET")
                if u1 and u2 then
                    ev:RegisterUnitEvent("UNIT_TARGET", u1, u2)
                elseif u1 or u2 then
                    ev:RegisterUnitEvent("UNIT_TARGET", u1 or u2)
                end
            end
        end
        local tk = PT.ticker
        if tk then
            if poll > 0 then
                if not tk:IsShown() then
                    PT.acc = 0
                    tk:Show()
                end
            elseif tk:IsShown() then
                tk:Hide()
            end
        end
        local ownOn = (own > 0 and PT.include) and true or false
        local ev = PT.ownFrame
        if ev and PT.ownEv ~= ownOn then
            PT.ownEv = ownOn
            if ownOn then
                ev:RegisterEvent("PLAYER_TARGET_CHANGED")
                ev:RegisterUnitEvent("UNIT_HEALTH", "target")
                ev:RegisterUnitEvent("UNIT_MAXHEALTH", "target")
                ev:RegisterUnitEvent("UNIT_FACTION", "target")
            else
                ev:UnregisterAllEvents()
            end
        end
    end

    -- The ticker (hidden while idle): every 0.5 s, the values of the polled frames on screen. A mob's
    -- colour follows its tap and reaction, which raise no events on these units: a change repaints.
    local function PT_Tick(_, elapsed)
        local acc = PT.acc + elapsed
        if acc < 0.5 then
            PT.acc = acc
            return
        end
        PT.acc = 0
        for _, frame in ipairs(mod._partyTargetFrames) do
            local u = frame._ptUnit
            if u and not frame._ptOwn and frame:IsVisible() and UnitExists(u) then
                PT_PaintValue(frame, u)
                if frame._ptNpc then
                    local re = UnitReaction(u, "player")
                    if issecretvalue(re) then
                        re = nil
                    end
                    if UnitIsTapDenied(u) ~= frame._ptTap or re ~= frame._ptRe then
                        PT_Paint(frame)
                    end
                end
            end
        end
    end

    -- Your target: a new target (or a faction change) repaints in full, its health events the value.
    local function PT_OnOwnEvent(_, evt)
        local full = evt == "PLAYER_TARGET_CHANGED" or evt == "UNIT_FACTION"
        for _, frame in ipairs(mod._partyTargetFrames) do
            if frame._ptOwn and frame:IsVisible() then
                if full then
                    PT_Paint(frame)
                elseif UnitExists("target") then
                    PT_PaintValue(frame, "target")
                end
            end
        end
    end

    -- Include Own Target off: the header frame showing you drops its target frame's unit. Written here
    -- out of combat by the rule the party frames' unit snippet applies in combat (PF.OWNER_SNIPPET).
    local function PT_SeedAttrs()
        local noself = (mod._ptEnabled and not PT.include) and true or nil
        local me = PT.me
        for _, widget in ipairs(mod._partyTargetFrames) do
            if widget ~= PT.selfFrame then
                if widget:GetAttribute("pt-noself") ~= noself then
                    widget:SetAttribute("pt-noself", noself)
                end
                if widget:GetAttribute("pt-me") ~= me then
                    widget:SetAttribute("pt-me", me)
                end
                local u = widget._ptOwner:GetAttribute("unit")
                local show = not (noself and u ~= nil and (u == "player" or u == me))
                if widget:GetAttribute("useparent-unit") ~= show then
                    widget:SetAttribute("useparent-unit", show)
                end
            end
        end
    end

    -- Full refresh (roster, zoning, the enable edge): your raid token, every frame's unit, the
    -- listeners, and a repaint of the frames on screen (a token can pass to another member). The
    -- attribute seed is a secure write: in combat it waits for the combat-end flush.
    mod._PT_RefreshAll = function()
        if not mod._ptEnabled then
            return
        end
        PT.me = PT_Me()
        for _, widget in ipairs(mod._partyTargetFrames) do
            PT_Classify(widget)
        end
        if InCombatLockdown() then
            mod._ptSelfDirty = true
        else
            PT_SeedAttrs()
        end
        PT_Recount()
        mod._PT_RepaintVisible()
    end

    -- Roster and zoning storms: one refresh on the next frame, after the header re-assigned its buttons.
    -- Nothing while the party frames are hidden (a raid): their show edge refreshes once instead
    -- (ns._UpdatePartyVisibility).
    PT.Flush = function()
        PT.flushQueued = nil
        mod._PT_RefreshAll()
    end

    local function PT_OnEvent(_, evt, unitToken)
        if evt == "UNIT_TARGET" then
            local widget = PT_BY_UNIT[unitToken]
            if widget and widget:IsVisible() then
                PT_Paint(widget)
            end
        elseif mod._partyFramesVisible and not PT.flushQueued then
            PT.flushQueued = true
            C_Timer.After(0, PT.Flush)
        end
    end

    -- The side (top/bottom read as above/below), the extra clearance there, and whether it runs across
    -- the stack. Across, the side resolves through the Party Frames kit, as the Beside Owner pets
    -- resolve theirs; along the stack it is kept as chosen, above stacked kit frames past the buff
    -- lines the kit keeps in the party spacing there (RF_PartyDims). auto: the side an unset Position
    -- takes, whatever is stored.
    local function PT_Side(s, auto)
        local place = (not auto and s.partyTargetPosition) or (s.partyHorizontal and "bottom" or "right")
        local side = (place == "top" and "above")
            or (place == "bottom" and "below")
            or (place == "left" and "left")
            or "right"
        local vert = side == "above" or side == "below"
        local extra = 0
        if (vert and not s.partyHorizontal) or (not vert and s.partyHorizontal) then
            if side == "above" and mod.RF_PartyKit() then
                local _, _, cs = mod.RF_PartyDims(s)
                extra = cs - (s.partyKitSpacing or mod.RF_KIT_SPACING)
                if extra < 0 then
                    extra = 0
                end
            end
            return side, extra, false
        end
        if mod.RF_PartyKit() then
            local before = side == "left" or side == "above"
            before, extra = mod.RF_KitAttach(s, before)
            if s.partyHorizontal then
                side = before and "above" or "below"
            else
                side = before and "left" or "right"
            end
        end
        return side, extra, true
    end

    -- The gap to the frame: the party frames' spacing (under the kit its frame gap, without the buff
    -- lines RF_PartyDims adds above stacked frames).
    local function PT_Gap(s)
        if mod.RF_PartyKit() then
            return s.partyKitSpacing or mod.RF_KIT_SPACING
        end
        local _, _, sp = mod.RF_PartyDims(s)
        return sp
    end

    -- The reach of target frames laid out as st (the live layout state PT, or a preview spec) past the
    -- party frames on the side a group attaches to (horizontal: the party frames' orientation; before:
    -- left, or above horizontal frames), offsets included. Across the stack: their room there, past
    -- the kit's clearance (the caller adds it) and any Beside Owner pets. Along the stack:
    -- how far they overhang the party frame's edge (a Width or Height past the frame's, an offset).
    local function PT_ReserveOf(st, horizontal, before)
        local side, region = st.side, 0
        if st.across then
            if horizontal then
                if before and side == "above" then
                    region = st.h + st.gap + st.y
                elseif not before and side == "below" then
                    region = st.h + st.gap - st.y
                end
            elseif before and side == "left" then
                region = st.w + st.gap - st.x
            elseif not before and side == "right" then
                region = st.w + st.gap + st.x
            end
        elseif horizontal then
            region = (st.h - st.ph) / 2 + (before and st.y or -st.y)
        else
            region = (st.w - st.pw) / 2 + (before and -st.x or st.x)
        end
        return region > 0 and PixelSnap(region) or 0
    end

    -- None until the frames are laid out (PT.w is cleared for a full layout). pets: the Beside Owner
    -- pets' room on that side, for a caller that clears them too: across the stack the target frames
    -- sit past them, along it level with them, so there the farther reach counts.
    function mod.PT_Reserve(horizontal, before, pets)
        pets = pets or 0
        if not (mod._ptEnabled and PT.w) then
            return pets
        end
        local region = PT_ReserveOf(PT, horizontal, before)
        if PT.across then
            return region + pets
        end
        return (region > pets) and region or pets
    end

    -- The Position the frames actually take (the options dropdown's value): under the Party Frames kit
    -- a side across the stack can move off the kit's buff run. auto: the one an unset setting takes
    -- (beside stacked frames, below horizontal ones, then that kit move); the dropdown stores a pick
    -- of it as unset, so the default keeps following the orientation and the frame style.
    function mod.PT_ShownSide(auto)
        local side = PT_Side(saved.profile, auto)
        return (side == "above" and "top") or (side == "below" and "bottom") or side
    end

    function mod.PT_PositionAlongStack(position, horizontal)
        return horizontal and (position == "left" or position == "right")
            or not horizontal and (position == "top" or position == "bottom")
    end

    -- Only direction is needed here; calculating the gap would call RF_PartyDims again.
    function mod.PT_AlongStack(s, enabled)
        if enabled == nil then
            enabled = mod._ptEnabled
        end
        return enabled and mod.PT_PositionAlongStack(s.partyTargetPosition, s.partyHorizontal) or false
    end

    -- Target length on the stacking axis plus the party gap. Previews pass their enable state.
    function mod.PT_AlongPitch(s, enabled)
        if not mod.PT_AlongStack(s, enabled) then
            return 0
        end
        return PixelSnap(s.partyHorizontal and (s.partyTargetWidth or 70) or (s.partyTargetHeight or 33))
            + PixelSnap(PT_Gap(s))
    end

    -- One target frame on its side of owner o: off from the owner's edge, then the offsets.
    local function PT_Place(widget, o, side, off, posX, posY)
        widget:ClearAllPoints()
        if side == "left" then
            widget:SetPoint("RIGHT", o, "LEFT", posX - off, posY)
        elseif side == "below" then
            widget:SetPoint("TOP", o, "BOTTOM", posX, posY - off)
        elseif side == "above" then
            widget:SetPoint("BOTTOM", o, "TOP", posX, posY + off)
        else
            widget:SetPoint("LEFT", o, "RIGHT", posX + off, posY)
        end
    end

    -- The reserve changed: re-anchor the groups that can attach beside the party frames (a Show in
    -- Dungeons boss group, the pet header). Both only move when their spot changed. OOC only.
    local function PT_NotifyReserve()
        local FB = mod._FB
        local fontStr = FB.Settings()
        if FB.built and fontStr and fontStr.showInDungeons == true then
            FB.Anchor()
        end
        mod.PF_ReAnchor()
    end

    -- Size and placement, delta-gated: every party layout pass (ns.PF_PartyRelayout, which the kit
    -- clearance edge reaches through ns.FB_ReAnchor), every Beside Owner pet change (ns._PF's
    -- NotifyReserve) and the Width, Height, Position and offset settings run it. The size is absolute
    -- (never the kit's Frame Scale). A combat call is marked for the combat-end flush (ns.PF_Flush).
    mod._PT_Layout = function()
        if not mod._ptEnabled then
            return
        end
        if InCombatLockdown() then
            mod._ptLayoutDirty = true
            return
        end
        mod._ptLayoutDirty = nil
        local s = saved.profile
        -- The party frames' pitch holds the frames along the stack: a change there re-lays the party
        -- frames first, and their pass ends back here.
        if mod._partyHeader and mod.PT_AlongPitch(s) ~= (mod._ptPitchApplied or 0) then
            mod._LayoutPartyFrames()
            return
        end
        local wid = PixelSnap(s.partyTargetWidth or 70)
        local hgt = PixelSnap(s.partyTargetHeight or 33)
        local posX = PixelSnap(s.partyTargetOffsetX or 0)
        local posY = PixelSnap(s.partyTargetOffsetY or 0)
        local pw, ph = mod.RF_PartyDims(s)
        pw, ph = PixelSnap(pw), PixelSnap(ph)
        local horiz = s.partyHorizontal and true or false
        local gap = PixelSnap(PT_Gap(s))
        local side, extra, across = PT_Side(s)
        local off = gap + PixelSnap(extra)
        -- Beside Owner pets on this side of the stack: after them (their gap already clears the kit).
        local popFrame = mod._PF
        if across and popFrame.ownerActive and popFrame.ownerSideCur == side then
            off = popFrame.ownerGap
                + ((side == "above" or side == "below") and popFrame.ownerH or popFrame.ownerW)
                + gap
        end
        local resized = wid ~= PT.w or hgt ~= PT.h
        -- The reserve's inputs (PT_ReserveOf): beside stacked frames the width and X offset, beside
        -- horizontal ones the height and Y offset, and along the stack the party frame's size too. A
        -- full layout (PT.w cleared) re-pins the attached groups, which read none meanwhile.
        local reserve = PT.w == nil
            or side ~= PT.side
            or across ~= PT.across
            or gap ~= PT.gap
            or horiz ~= PT.horiz
        if not reserve then
            if horiz then
                reserve = hgt ~= PT.h or posY ~= PT.y or (not across and ph ~= PT.ph)
            else
                reserve = wid ~= PT.w or posX ~= PT.x or (not across and pw ~= PT.pw)
            end
        end
        PT.pw, PT.ph, PT.horiz = pw, ph, horiz
        if not (reserve or resized) and off == PT.off and posX == PT.x and posY == PT.y then
            return
        end
        PT.w, PT.h, PT.side, PT.gap, PT.off, PT.across, PT.x, PT.y =
            wid, hgt, side, gap, off, across, posX, posY
        local sizeVisuals = mod._FB.SizeVisuals
        for _, widget in ipairs(mod._partyTargetFrames) do
            if resized then
                widget:SetSize(wid, hgt)
                sizeVisuals(widget, wid, hgt)
                widget._nameText:SetWidth(max(1, wid - 6))
            end
            PT_Place(widget, widget._ptOwner, side, off, posX, posY)
        end
        if reserve then
            PT_NotifyReserve()
        end
    end

    -- The target frames' own style inputs after the shared ones: Fill Color and its custom colour,
    -- Background (class or custom colour, darkness) and Smooth Bars.
    local function PT_FpExtra(t)
        local p, num = saved.profile, mod._PF.STYLE_N
        local fc = p.partyTargetCustomFillColor or PT.DEF_FILL
        local bc = p.partyTargetCustomBgColor or mod._PF.DEFAULT_BG
        t[num + 1], t[num + 2], t[num + 3], t[num + 4] = p.partyTargetHealthColorMode, fc.r, fc.g, fc.b
        t[num + 5], t[num + 6], t[num + 7], t[num + 8] = p.partyTargetBgClassColored, bc.r, bc.g, bc.b
        t[num + 9], t[num + 10] = p.partyTargetBgDarkness, PT_Source().smoothBars
    end

    -- Textured Background on a target frame, from the party settings: the fixed health
    -- layer (the background follows the fill edge), shown while the fill is opaque.
    local function PT_TexBg(widget)
        local s = PT_Source()
        local filePath = mod.RF_TexBgPath(s)
        if not (filePath or widget._rfTexBg) then
            return
        end
        widget._rfTexBg = filePath and true or nil
        local dark = saved.profile.partyTargetHealthColorMode == "dark"
        mod.RF_TexBgLayer(
            widget._health,
            widget._bg,
            (not dark or mod.RF_TexBgOpaque(s, true)) and filePath or nil
        )
        if filePath then
            mod.RF_TexBgWatch()
        end
    end
    -- A colour push (ns.RF_TexBgRecheck): Dark Mode Fill can cross 100 with no restyle.
    -- ERF:UpdateAllFrames repaints the frames on screen right after.
    mod._PT_TexBgRecheck = function()
        if not mod._ptEnabled then
            return
        end
        for _, widget in ipairs(mod._partyTargetFrames) do
            PT_TexBg(widget)
        end
    end

    -- Texture, name font and border from the party settings (the stock edge under a stock style), and
    -- the colour settings the paint reads, fingerprinted together: a reload or setting that changed
    -- none of them touches nothing; one that did repaints the frames on screen, restyling them only
    -- when a shared input changed (a colour setting alone re-reads the colours). A change made while
    -- off lands on the enable edge. Combat-legal: nothing here touches the secure buttons.
    mod._PT_Restyle = function()
        if not mod._ptEnabled then
            return
        end
        local s = PT_Source()
        local texPath = ResolveHealthTexture(s)
        local changed, at = mod._PF.StyleChanged("pt", s, texPath, PT_FpExtra, PT.FP_N)
        if not changed then
            return
        end
        local p = saved.profile
        local fc = p.partyTargetCustomFillColor or PT.DEF_FILL
        local bc = p.partyTargetCustomBgColor or mod._PF.DEFAULT_BG
        PT.mode = p.partyTargetHealthColorMode or "class"
        PT.fr, PT.fg, PT.fb = fc.r, fc.g, fc.b
        PT.bgClass = p.partyTargetBgClassColored and true or nil
        PT.br, PT.bgg, PT.bb = bc.r, bc.g, bc.b
        PT.bgA = (p.partyTargetBgDarkness or 50) / 100
        local interp = Enum.StatusBarInterpolation
        PT.smooth = (s.smoothBars and interp and interp.ExponentialEaseOut) or nil
        -- 0: nothing styled yet (new frames); up to STYLE_N: a shared input changed.
        if at <= mod._PF.STYLE_N then
            local nameSize = s.nameSize or 10
            local styleBorder = mod._FB.StyleBorder
            for _, widget in ipairs(mod._partyTargetFrames) do
                local health, backdrop = widget._health, widget._bg
                health:SetStatusBarTexture(texPath)
                local texture = health:GetStatusBarTexture()
                backdrop:ClearAllPoints()
                if texture then
                    texture:SetHorizTile(false)
                    -- The background covers the missing health only, off the fill's far edge.
                    backdrop:SetPoint("TOPLEFT", texture, "TOPRIGHT", 0, 0)
                    backdrop:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
                else
                    backdrop:SetAllPoints(health)
                end
                ApplyFont(widget._nameText, nameSize)
                styleBorder(widget)
            end
        end
        for _, widget in ipairs(mod._partyTargetFrames) do
            PT_TexBg(widget)
        end
        mod._PT_RepaintVisible()
    end

    -- Hover border, as the pets and the boss group.
    local function PT_Enter(self)
        mod._FB.hov[self] = true
        mod._FB.ApplyBorderColor(self)
    end
    local function PT_Leave(self)
        mod._FB.hov[self] = nil
        mod._FB.ApplyBorderColor(self)
    end

    -- A frame coming on screen (its unit appeared, or its party frame showed): its unit re-read and a
    -- full paint. Going off screen: the listeners follow.
    local function PT_OnShow(self)
        if not mod._ptEnabled then
            return
        end
        PT_Classify(self)
        PT_Paint(self)
        PT_Recount()
    end
    local function PT_OnHide(self)
        PT_Recount(self)
    end

    -- The party header re-assigned an owner's unit (in combat too): its target frame follows at once.
    -- The same unit set again (every header pass) returns after the compare.
    local function PT_OwnerAttr(ownerFrame, name)
        if name ~= "unit" or not mod._ptEnabled then
            return
        end
        local widget = PT.frameOf[ownerFrame]
        if widget and PT_Classify(widget) and widget:IsVisible() then
            PT_Paint(widget)
            PT_Recount()
        end
    end

    -- Real-frame previews hide the real frames by alpha; while they do, a mouse blocker on each target
    -- frame (they sit outside the party frames' blocker) keeps the invisible buttons from taking
    -- clicks. Our frames, so Hide() is combat-legal; each blocker hides with its target frame.
    mod._PT_SetPreviewBlock = function(enabled)
        PT.pvBlockOn = enabled or nil
        for _, widget in ipairs(mod._partyTargetFrames) do
            local blk = widget._ptBlock
            if enabled and mod._ptEnabled then
                if not blk then
                    blk = CreateFrame("Frame", nil, widget)
                    blk:SetAllPoints(widget)
                    blk:EnableMouse(true)
                    widget._ptBlock = blk
                end
                blk:SetFrameLevel(widget:GetFrameLevel() + 50)
                blk:Show()
            elseif blk then
                blk:Hide()
            end
        end
    end

    -- The enable/disable edges, a new frame and a frame strata change while blocked: re-seat the
    -- blockers.
    mod._PT_RefreshPreviewBlock = function()
        if PT.pvBlockOn then
            mod._PT_SetPreviewBlock(true)
        end
    end

    local function PT_Build(ownerFrame, globalName)
        local widget = CreateFrame("Button", globalName, ownerFrame, "SecureUnitButtonTemplate")
        widget:SetAttribute("useparent-unit", true)
        widget:SetAttribute("unitsuffix", "target")
        widget:SetAttribute("*type1", "target")
        widget:RegisterForClicks("AnyUp")
        widget:Hide()

        -- Background, health bar, name text and border frame (the stock edge under a stock style).
        -- The font comes with the next restyle, before the frame can show.
        local FB = mod._FB
        FB.BuildVisuals(widget)
        local name = widget._nameText
        name:SetPoint("CENTER", widget._health, "CENTER", 0, 0)
        name:SetJustifyH("CENTER")
        name:SetJustifyV("MIDDLE")
        name:SetTextColor(1, 1, 1, 1)

        widget._ptOwner = ownerFrame
        FB.src[widget] = PT_Source
        widget:HookScript("OnShow", PT_OnShow)
        widget:HookScript("OnHide", PT_OnHide)
        widget:HookScript("OnEnter", PT_Enter)
        widget:HookScript("OnLeave", PT_Leave)
        -- Header buttons: the unit snippet reaches the frame through a frame ref, and a unit
        -- re-assignment re-reads it (a lookup table, never a key on the header's button).
        if ownerFrame ~= mod._partySelfButton then
            PT.frameOf[ownerFrame] = widget
            SecureHandlerSetFrameRef(ownerFrame, "ptframe", widget)
            ownerFrame:HookScript("OnAttributeChanged", PT_OwnerAttr)
        end
        table.insert(mod._partyTargetFrames, widget)
        return widget
    end

    -- The self button's frame (Show Self First / Last: its unit is "player", so it shows your target;
    -- it hides with the self button while that is unused), built the first time Include Own Target is
    -- on. True when built now. OOC only.
    local function PT_EnsureSelf()
        if PT.selfFrame or not mod._partySelfButton then
            return false
        end
        PT.selfFrame = PT_Build(mod._partySelfButton, "ERFPartyTargetSelf")
        -- New frames take the next restyle in full.
        mod._PF.fp.pt = nil
        return true
    end

    -- One per party header button, built on the first enable. OOC only.
    mod._PT_Create = function()
        if not mod._ptCreated and mod._partyHeader then
            mod._ptCreated = true
            for i = 1, 5 do
                local ownerFrame = mod._partyHeader[i]
                if ownerFrame then
                    PT_Build(ownerFrame, "ERFPartyTarget" .. i)
                end
            end
            mod._PF.fp.pt = nil
        end
        if mod._ptInclDesired then
            PT_EnsureSelf()
        end
    end

    -- Include Own Target, applied: the self button's frame (built on first use) watched only while on,
    -- the attributes and unit snippet that gate the header frame showing you, and your target's
    -- listeners. Secure writes: out of combat; a combat call waits for the combat-end flush.
    local function PT_ApplyInclude()
        if InCombatLockdown() then
            mod._ptSelfDirty = true
            return
        end
        mod._ptSelfDirty = nil
        local inc = (mod._ptEnabled and mod._ptInclDesired) and true or nil
        PT.include = inc
        if inc and PT_EnsureSelf() then
            -- Sized, placed and styled before it can show.
            PT.w = nil
            mod._PT_Layout()
            mod._PT_Restyle()
            mod._PT_RefreshPreviewBlock()
        end
        local scrollFrame = PT.selfFrame
        if scrollFrame and PT.selfWatched ~= inc then
            PT.selfWatched = inc
            if inc then
                PT_Classify(scrollFrame)
                RegisterUnitWatch(scrollFrame)
            else
                UnregisterUnitWatch(scrollFrame)
                scrollFrame:Hide()
            end
        end
        mod._ptNoSelf = (mod._ptEnabled and not inc) and true or nil
        PT_SeedAttrs()
        mod.PF_SyncUnitSnippet()
        PT_Recount()
    end

    -- The combat-end flush (ns.PF_Flush) of a deferred include edge or attribute seed.
    mod._PT_SyncSelf = function()
        mod._ptSelfDirty = nil
        if mod._ptEnabled then
            PT_ApplyInclude()
        end
    end

    mod._PT_Apply = function()
        if mod._ptDesired == mod._ptEnabled then
            return
        end
        if InCombatLockdown() then
            mod.CombatQueue.Defer("PT_Apply", mod._PT_Apply)
            return
        end
        if mod._ptDesired then
            mod._PT_Create()
            -- The listeners, made once: roster and zoning, UNIT_TARGET (three, two units each), your
            -- target's events, and the hidden value ticker.
            if not mod._ptEventFrame then
                local frame = mod.TakeShell()
                frame:SetScript("OnEvent", PT_OnEvent)
                mod._ptEventFrame = frame
                for k = 1, 3 do
                    frame = mod.TakeShell()
                    frame:SetScript("OnEvent", PT_OnEvent)
                    PT.tgtEv[k] = frame
                end
                frame = mod.TakeShell()
                frame:SetScript("OnEvent", PT_OnOwnEvent)
                PT.ownFrame = frame
                frame = mod.TakeShell()
                frame:Hide()
                frame:SetScript("OnUpdate", PT_Tick)
                PT.ticker = frame
            end
            local events = mod._ptEventFrame
            events:RegisterEvent("GROUP_ROSTER_UPDATE")
            events:RegisterEvent("PLAYER_ENTERING_WORLD")
            mod._ptEnabled = true
            PT.include = mod._ptInclDesired or nil
            -- A full layout (the attached groups gain the reserve), a style check and the units, then
            -- the frames come up: the attributes gating yours are set before the watches.
            PT.w = nil
            mod._PT_Layout()
            mod._PT_Restyle()
            mod._PT_RefreshAll()
            PT_ApplyInclude()
            for _, widget in ipairs(mod._partyTargetFrames) do
                if widget ~= PT.selfFrame then
                    RegisterUnitWatch(widget)
                end
            end
        else
            mod._ptEnabled = false
            mod._ptEventFrame:UnregisterAllEvents()
            for _, widget in ipairs(mod._partyTargetFrames) do
                UnregisterUnitWatch(widget)
                widget:Hide()
            end
            PT.include, PT.selfWatched, mod._ptNoSelf = nil, nil, nil
            mod._ptLayoutDirty, mod._ptSelfDirty = nil, nil
            -- Every listener and the ticker off; the gate attributes cleared, so a unit snippet kept for
            -- the pets leaves the target frames alone.
            PT_Recount()
            PT_SeedAttrs()
            mod.PF_SyncUnitSnippet()
            -- The party frames close the pitch the frames held along the stack, and the attached
            -- groups take the room back.
            if (mod._ptPitchApplied or 0) ~= 0 then
                mod._LayoutPartyFrames()
            end
            PT_NotifyReserve()
        end
        mod._PT_RefreshPreviewBlock()
    end

    mod.PT_SetEnabled = function(enabled)
        mod._ptDesired = enabled and true or false
        mod._PT_Apply()
    end

    -- Include Own Target (options, profile swaps): applied now while on, else on the enable edge.
    mod.PT_SetIncludeSelf = function(enabled)
        mod._ptInclDesired = enabled and true or false
        if mod._ptEnabled then
            PT_ApplyInclude()
        end
    end

    -- A Fill Color or Background setting changed (the options): the fingerprint-gated restyle, which
    -- repaints the frames on screen when anything it reads changed. Nothing while off.
    mod.PT_Refresh = function()
        if mod._ptEnabled then
            mod._PT_Restyle()
        end
    end

    -- Options preview: a made-up target beside each party preview frame while Party Targets is on, on
    -- the real frames' visuals and with their size, side, offsets and colours. Plain frames, built the
    -- first time a preview shows them; ns.PT_PreviewSpec measures them and the room they need.
    PT.pv, PT.pvSpec = {}, {}
    PT.PV = {
        { name = "Gnoll Brute", hp = 72, re = 2 },
        { name = "Kobold Miner", hp = 100, re = 4 },
        { name = "Defias Thug", hp = 38, re = 2 },
        { name = "Murloc Raider", hp = 85, re = 2 },
        { name = "Bristleback Boar", hp = 55, re = 4 },
    }

    -- The preview's target layout, or nil while Party Targets is off: as the real frames take it
    -- (after the Beside Owner pets on their side: petSpec, the pets' preview spec), plus how far a
    -- frame reaches past its party frame's edges (pads). s: the preview's view; pw, ph: its party
    -- frame size. One reused table.
    function mod.PT_PreviewSpec(s, pw, ph, petSpec)
        if s.partyShowTargets ~= true then
            return nil
        end
        local t = PT.pvSpec
        local wid, hgt = PixelSnap(s.partyTargetWidth or 70), PixelSnap(s.partyTargetHeight or 33)
        local posX, posY = PixelSnap(s.partyTargetOffsetX or 0), PixelSnap(s.partyTargetOffsetY or 0)
        local gap = PixelSnap(PT_Gap(s))
        local side, extra, across = PT_Side(s)
        local off = gap + PixelSnap(extra)
        if across and petSpec and petSpec.owner and petSpec.side == side then
            off = petSpec.gap + ((side == "above" or side == "below") and petSpec.h or petSpec.w) + gap
        end
        t.w, t.h, t.x, t.y, t.gap, t.off, t.side, t.across, t.pw, t.ph =
            wid, hgt, posX, posY, gap, off, side, across, pw, ph
        -- The frame's box from its party frame's centre.
        local l, b
        if side == "left" then
            l, b = posX - off - pw / 2 - wid, posY - hgt / 2
        elseif side == "right" then
            l, b = posX + off + pw / 2, posY - hgt / 2
        elseif side == "below" then
            l, b = posX - wid / 2, posY - off - ph / 2 - hgt
        else
            l, b = posX - wid / 2, posY + off + ph / 2
        end
        t.padL, t.padR = max(0, -pw / 2 - l), max(0, l + wid - pw / 2)
        t.padB, t.padT = max(0, -ph / 2 - b), max(0, b + hgt - ph / 2)
        return t
    end

    -- The room a preview spec takes beside the preview's party frames (the pets beside them), as
    -- ns.PT_Reserve gives the real frames'.
    function mod.PT_PreviewReserve(specInfo, horizontal, before)
        return specInfo and PT_ReserveOf(specInfo, horizontal, before) or 0
    end

    -- Preview target i at the spec's size: styled from the party settings, painted from the view s
    -- (made-up mobs: Class Color reads their reaction).
    local function PT_PvFrame(i, hostFrame, s, specInfo)
        local FB = mod._FB
        local frame = PT.pv[i]
        if not frame then
            frame = CreateFrame("Frame", nil, hostFrame)
            FB.BuildVisuals(frame)
            FB.src[frame] = PT_Source
            local name = frame._nameText
            name:SetPoint("CENTER", frame._health, "CENTER", 0, 0)
            name:SetJustifyH("CENTER")
            name:SetJustifyV("MIDDLE")
            name:SetTextColor(1, 1, 1, 1)
            PT.pv[i] = frame
        elseif frame:GetParent() ~= hostFrame then
            frame:SetParent(hostFrame)
        end
        frame:SetFrameStrata(hostFrame == UIParent and "HIGH" or hostFrame:GetFrameStrata())
        local wid, hgt = specInfo.w, specInfo.h
        frame:SetSize(wid, hgt)
        FB.SizeVisuals(frame, wid, hgt)
        local st = PT_Source()
        local health, backdrop, name = frame._health, frame._bg, frame._nameText
        health:SetStatusBarTexture(ResolveHealthTexture(st))
        local texture = health:GetStatusBarTexture()
        backdrop:ClearAllPoints()
        if texture then
            texture:SetHorizTile(false)
            backdrop:SetPoint("TOPLEFT", texture, "TOPRIGHT", 0, 0)
            backdrop:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
        else
            backdrop:SetAllPoints(health)
        end
        ApplyFont(name, st.nameSize or 10)
        name:SetWidth(max(1, wid - 6))
        FB.StyleBorder(frame)
        local mock = PT.PV[i]
        health:SetMinMaxValues(0, 100)
        health:SetValue(mock.hp)
        name:SetText(mock.name)
        local mode = s.partyTargetHealthColorMode or "class"
        mod.RF_TexBgLayer(
            health,
            backdrop,
            (mode ~= "dark" or mod.RF_TexBgOpaque(st, true)) and mod.RF_TexBgPath(st) or nil
        )
        if mode == "dark" then
            local region, g, b, a = CUI.GetDarkModeFill()
            health:SetStatusBarColor(region, g, b, 1)
            if texture then
                texture:SetAlpha(a)
            end
            backdrop:SetColorTexture(CUI.GetDarkModeBg())
        else
            if texture then
                texture:SetAlpha(1)
            end
            local rc = FACTION_BAR_COLORS[mock.re]
            if mode == "classic" then
                local p = mock.hp / 100
                health:SetStatusBarColor(p < 0.5 and 1 or (1 - (p - 0.5) * 2), p > 0.5 and 1 or (p * 2), 0, 1)
            elseif mode == "custom" then
                local c = s.partyTargetCustomFillColor or PT.DEF_FILL
                health:SetStatusBarColor(c.r, c.g, c.b, 1)
            else
                health:SetStatusBarColor(rc.r, rc.g, rc.b, 1)
            end
            local a = (s.partyTargetBgDarkness or 50) / 100
            if s.partyTargetBgClassColored then
                backdrop:SetColorTexture(rc.r, rc.g, rc.b, a)
            else
                local c = s.partyTargetCustomBgColor or mod._PF.DEFAULT_BG
                backdrop:SetColorTexture(c.r, c.g, c.b, a)
            end
        end
        frame:Show()
        return frame
    end

    -- The preview targets beside the party preview frames on screen, parented to parent (skip: your
    -- own frame's index, without Include Own Target), or none without a spec.
    function mod.PT_ShowPreview(specInfo, s, hostFrame, skip)
        local num = 0
        if specInfo then
            for i = 1, 5 do
                local o = mod._partyPvFrames[i]
                if o and o:IsShown() and i ~= skip then
                    num = num + 1
                    PT_Place(
                        PT_PvFrame(num, hostFrame, s, specInfo),
                        o,
                        specInfo.side,
                        specInfo.off,
                        specInfo.x,
                        specInfo.y
                    )
                end
            end
        end
        for i = num + 1, #PT.pv do
            PT.pv[i]:Hide()
        end
    end

    function mod.PT_HidePreview()
        for _, frame in ipairs(PT.pv) do
            frame:Hide()
        end
    end
end -- Party Targets scope block

Inner.broken = false
