if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_RaidFrames_PetFrames.lua
--
--  Pet Frames: party and raid pets in one pet header, or beside their owner.
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
local tostring = tostring
local UnitExists = UnitExists
local UnitIsUnit = UnitIsUnit
local UnitInRange = UnitInRange
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local InCombatLockdown = InCombatLockdown
local issecretvalue = issecretvalue
local CreateFrame = CreateFrame

local GetFFD, PixelSnap, ResolveHealthTexture = Inner.GetFFD, Inner.PixelSnap, Inner.ResolveHealthTexture

local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(v)
    saved = v
end

-------------------------------------------------------------------------------
--  Pet Frames: party and raid pets in one Blizzard pet header, beside the
--  groups like Friendly Boss, or (Party tab, Beside Owner) one pet button
--  beside each party frame. Health, name, range, hover/target borders and
--  click-cast only, on the FB visuals, painter and anchor; out of the raid
--  routing maps, trackers of their own. Built on first Show Pets.
-------------------------------------------------------------------------------
do
    local FB = mod._FB
    local PopFrame = {
        buttons = {},
        trackers = {},
        byUnit = {},
        ownerButtons = {},
        ownerByUnit = {},
        watching = false,
        shownEv = false,
        tgtEv = false,
        petEv = false,
        tgtWanted = false,
    }
    mod._PF = PopFrame

    PopFrame.MAX = 40
    PopFrame.UNITS = { "pet" }
    for idx = 1, 4 do
        PopFrame.UNITS[#PopFrame.UNITS + 1] = "partypet" .. idx
    end
    for idx = 1, 40 do
        PopFrame.UNITS[#PopFrame.UNITS + 1] = "raidpet" .. idx
    end
    -- Tracker frames (two tokens each): every token, or while raid pets are off the first seven, which
    -- hold your pet, the party pets and raidpet1-9 (inside a raid the party frames run below ten
    -- members).
    PopFrame.ALL_TRACKERS = math.ceil(#PopFrame.UNITS / 2)
    PopFrame.SMALL_TRACKERS = 7
    PopFrame.EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE" }
    -- A party frame's token -> its pet's token.
    PopFrame.PET_OF = { player = "pet" }
    for idx = 1, 4 do
        PopFrame.PET_OF["party" .. idx] = "partypet" .. idx
    end
    for idx = 1, 40 do
        PopFrame.PET_OF["raid" .. idx] = "raidpet" .. idx
    end
    PopFrame.DEFAULT_BG = { r = 17 / 255, g = 17 / 255, b = 17 / 255 }
    -- Beside Owner pet -> the party frame it sits beside (your own pet has none); header button -> the
    -- style generation it was last styled at; Beside Owner pet -> its preview mouse blocker.
    PopFrame.ownerOf = setmetatable({}, { __mode = "k" })
    PopFrame.styledGen = setmetatable({}, { __mode = "k" })
    PopFrame.pvBlock = setmetatable({}, { __mode = "k" })

    PopFrame.Raw = function()
        return saved and saved.profile and saved.profile.petFrames
    end
    -- The painter's Pet Health Color read (one setting for both tabs, off the per-tab view).
    PopFrame.ColorSettings = PopFrame.Raw

    -- The Party and Raid tabs each keep their own Position, Extra Width/Height, Free Move spot and Free
    -- Move Growth Direction. A tab reads the shared key until it sets its own: a view over the saved
    -- table that never writes on read. Every other key (the tab toggles, Pet Health Color, Pet Side) is
    -- the saved one.
    PopFrame.TAB_KEY = {
        party = {
            position = "party_position",
            extraWidth = "party_extraWidth",
            extraHeight = "party_extraHeight",
            freePos = "party_freePos",
            freeRect = "party_freeRect",
            freeGrowth = "party_freeGrowth",
        },
        raid = {
            position = "raid_position",
            extraWidth = "raid_extraWidth",
            extraHeight = "raid_extraHeight",
            freePos = "raid_freePos",
            freeRect = "raid_freeRect",
            freeGrowth = "raid_freeGrowth",
        },
    }
    PopFrame.views = {}
    PopFrame.View = function(context)
        local v = PopFrame.views[context]
        if v then
            return v
        end
        local keyList = PopFrame.TAB_KEY[context]
        v = setmetatable({}, {
            __index = function(_, k)
                local raw = PopFrame.Raw()
                if not raw then
                    return nil
                end
                local tk = keyList[k]
                if tk then
                    local val = raw[tk]
                    if val ~= nil then
                        return val
                    end
                end
                return raw[k]
            end,
            __newindex = function(_, k, val)
                local raw = PopFrame.Raw()
                if raw then
                    raw[keyList[k] or k] = val
                end
            end,
        })
        PopFrame.views[context] = v
        return v
    end
    mod.PF_View = PopFrame.View

    -- The toggle that counts is the one for the frames on screen: the party frames also run inside
    -- small raids and arenas.
    PopFrame.PartyMode = function()
        return not IsInRaid() or mod._PartyInRaid()
    end

    PopFrame.Ctx = function()
        return PopFrame.PartyMode() and "party" or "raid"
    end

    -- The live tab's view.
    PopFrame.Settings = function()
        return PopFrame.Raw() and PopFrame.View(PopFrame.Ctx())
    end

    -- Beside Owner: Show Pets on the Party tab with its Position on Beside Owner, while the party frames
    -- are the ones on screen.
    PopFrame.OwnerChosen = function()
        local raw = PopFrame.Raw()
        return (
            raw
            and raw.party == true
            and PopFrame.PartyMode()
            and PopFrame.View("party").position == "owner"
        ) or false
    end

    -- The pet header (Beside Owner leaves it down).
    PopFrame.Wanted = function()
        local raw = PopFrame.Raw()
        if not raw then
            return false
        end
        if PopFrame.PartyMode() then
            return raw.party == true and PopFrame.View("party").position ~= "owner"
        end
        return raw.raid == true
    end

    -- Settings the pets are styled from: the party settings beside the party frames, else the raid's.
    -- The header's follows the mode PF.Layout last laid it out for (PF.styleCtx), so the paint path
    -- never re-derives the mode.
    PopFrame.PartySource = function()
        return mod._scaledPartyProxy
    end
    PopFrame.StyleSource = function()
        if PopFrame.styleCtx == "party" then
            return mod._scaledPartyProxy
        end
        return mod._scaledProfile or saved.profile
    end

    -- Beside Owner pets ignore their party frame's alpha (its range, offline and Buff Manager fades
    -- are the owner's), so the party container's own dims (the options previews) apply here instead.
    PopFrame.ContainerAlpha = function()
        local a = mod._partyContainerFrame:GetAlpha()
        if issecretvalue(a) then
            return 1
        end
        return a
    end

    -- As the raid buttons: UnitInRange's first return straight into SetAlphaFromBoolean, which takes
    -- a secret. Its unchecked case is your own units, so your pet stays at full alpha like you do.
    PopFrame.ApplyRange = function(b)
        local unitToken = FB.UnitOf(b)
        if not unitToken then
            return
        end
        local ca = PopFrame.ownerOf[b] and PopFrame.ContainerAlpha() or 1
        local own = UnitIsUnit(unitToken, "pet")
        if issecretvalue(own) then
            own = false
        end
        if not UnitExists(unitToken) or own then
            b:SetAlpha(ca)
            return
        end
        local s = FB.Source(b)
        b:SetAlphaFromBoolean(UnitInRange(unitToken), ca, (s.oorAlpha or 0.4) * ca)
    end

    -- fn(b, unit) on every pet button on screen: the header's, and beside the party frames the Beside
    -- Owner pets and your own pet button.
    PopFrame.EachShown = function(func)
        if PopFrame.active then
            for u, b in pairs(PopFrame.byUnit) do
                if b:IsVisible() then
                    func(b, u)
                end
            end
        end
        if PopFrame.ownerActive then
            for u, b in pairs(PopFrame.ownerByUnit) do
                if b:IsVisible() then
                    func(b, u)
                end
            end
            local sp = PopFrame.selfPet
            if sp:IsVisible() then
                func(sp, "pet")
            end
        end
    end

    -- Whether a target change can repaint anything: Target Border on in the settings the pets that are
    -- up are styled from. Re-read by every apply and party restyle (PF.SyncListeners).
    PopFrame.TargetWanted = function()
        local s = PopFrame.active and PopFrame.StyleSource()
        if s and s.targetBorderEnabled ~= false then
            return true
        end
        s = PopFrame.ownerActive and PopFrame.PartySource()
        return (s and s.targetBorderEnabled ~= false) and true or false
    end

    -- Every pet listener runs only while a pet button is on screen (the header hidden solo or in a pet
    -- battle, or the party frames down, leaves none): the trackers' health, name and range, the vehicle
    -- edges, UNIT_PET beside the party frames, and target changes while a Target Border can show. A
    -- button coming on screen paints in full, which covers whatever it missed.
    PopFrame.SyncShownEvents = function()
        local wanted = (PopFrame.tracking and (PopFrame.visCount or 0) > 0) and true or false
        local ev = PopFrame.eventFrame
        local tgt = wanted and PopFrame.tgtWanted
        if PopFrame.tgtEv ~= tgt then
            PopFrame.tgtEv = tgt
            if tgt then
                ev:RegisterEvent("PLAYER_TARGET_CHANGED")
            else
                ev:UnregisterEvent("PLAYER_TARGET_CHANGED")
            end
        end
        local pet = (wanted and PopFrame.ownerActive) and true or false
        if PopFrame.petEv ~= pet then
            PopFrame.petEv = pet
            if pet then
                ev:RegisterEvent("UNIT_PET")
            else
                ev:UnregisterEvent("UNIT_PET")
            end
        end
        if PopFrame.shownEv == wanted then
            return
        end
        PopFrame.shownEv = wanted
        if wanted then
            ev:RegisterEvent("UNIT_ENTERED_VEHICLE")
            ev:RegisterEvent("UNIT_EXITED_VEHICLE")
        else
            ev:UnregisterEvent("UNIT_ENTERED_VEHICLE")
            ev:UnregisterEvent("UNIT_EXITED_VEHICLE")
        end
        for _, tr in ipairs(PopFrame.trackers) do
            PopFrame.TrackerEvents(tr, wanted)
        end
    end

    -- The listeners after an apply or a party restyle, which can change the pets that are up and the
    -- Target Border setting.
    PopFrame.SyncListeners = function()
        PopFrame.tgtWanted = PopFrame.TargetWanted()
        PopFrame.SyncShownEvents()
    end

    -- One tracker's health, name and range listeners. Your own pet takes no range fade, so its token is
    -- left out of range.
    PopFrame.TrackerEvents = function(tr, enabled)
        local f = tr.frame
        if not enabled then
            f:UnregisterAllEvents()
            return
        end
        for _, ev in ipairs(PopFrame.EVENTS) do
            f:RegisterUnitEvent(ev, tr.u1, tr.u2)
        end
        if tr.u1 == "pet" then
            f:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", tr.u2)
        else
            f:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", tr.u1, tr.u2)
        end
    end

    -- Range re-read with no range update behind it (phasing, the Out of Range Alpha slider, roster
    -- passes): the tail of the raid frames' own range seed.
    function mod._PF_RangeSeed()
        if PopFrame.shownEv then
            PopFrame.EachShown(PopFrame.ApplyRange)
        end
    end

    -- A group member's connection changed: re-read its pet's range.
    function mod._PF_OwnerRange(ownerFrame)
        local pt = PopFrame.shownEv and PopFrame.PET_OF[ownerFrame]
        if not pt then
            return
        end
        local b = PopFrame.active and PopFrame.byUnit[pt]
        if b and b:IsVisible() then
            PopFrame.ApplyRange(b)
        end
        b = PopFrame.ownerActive and PopFrame.ownerByUnit[pt]
        if b and b:IsVisible() then
            PopFrame.ApplyRange(b)
        end
    end

    -- A target change repaints only the pets whose target state flipped (the old and new target).
    PopFrame.TargetFlip = function(b, u)
        if FB.ReadTarget(b, u) then
            FB.ApplyBorderColor(b)
        end
    end

    -- The full paint, which stamps the occupant it painted (unit + GUID, a secret GUID never stored) so
    -- a re-assignment of the same pet can skip it. A pet that does not exist yet still gets its border.
    PopFrame.Refresh = function(b)
        if not FB.Update(b, PopFrame) then
            FB.ApplyBorderColor(b)
        end
        PopFrame.ApplyRange(b)
        local u = FB.UnitOf(b)
        local g = u and UnitGUID(u)
        if issecretvalue(g) then
            g = nil
        end
        local d = GetFFD(b)
        d.pfPaintUnit, d.pfGuid = u, g
    end

    -- Repaints a shown button only when its occupant differs from the stamped one (a secret or missing
    -- GUID always repaints).
    PopFrame.Revalidate = function(b)
        if not (b and b:IsVisible()) then
            return
        end
        local u = FB.UnitOf(b)
        local d = GetFFD(b)
        if u and u == d.pfPaintUnit then
            local g = UnitGUID(u)
            if issecretvalue(g) then
                g = nil
            end
            if g and g == d.pfGuid then
                return
            end
        end
        PopFrame.Refresh(b)
    end

    -- Every pet button on screen (cross-module colour and name pushes).
    function mod._PF_RefreshVisible()
        PopFrame.EachShown(PopFrame.Refresh)
    end

    -- The buttons of one list that are on screen (PF.buttons or PF.ownerButtons), after a settings
    -- reload or a party/raid flip.
    PopFrame.RepaintShown = function(entries)
        for _, b in ipairs(entries) do
            if b:IsVisible() then
                PopFrame.Refresh(b)
            end
        end
    end

    -- The pet behind one owner's token may have changed while its button kept the same unit attribute:
    -- a new pet (UNIT_PET, Beside Owner only: the pet header re-assigns its own buttons on it), or the
    -- owner entering or leaving a vehicle, which the pet token then stands for. Only that owner's pet
    -- buttons are re-checked. owner: the event's unit.
    PopFrame.OnPetChanged = function(ownerFrame)
        local pt = ownerFrame and PopFrame.PET_OF[ownerFrame]
        if not pt then
            return
        end
        if PopFrame.active then
            PopFrame.Revalidate(PopFrame.byUnit[pt])
        end
        if PopFrame.ownerActive then
            PopFrame.Revalidate(PopFrame.ownerByUnit[pt])
            if pt == "pet" then
                PopFrame.Revalidate(PopFrame.selfPet)
            end
        end
    end

    -- The party container's alpha changed (the options previews): re-apply the Beside Owner pets'.
    function mod._PF_AlphaSync()
        if not PopFrame.ownerActive then
            return
        end
        for _, b in ipairs(PopFrame.ownerButtons) do
            if PopFrame.ownerOf[b] and b:IsVisible() then
                PopFrame.ApplyRange(b)
            end
        end
    end

    -- The side a group attached beside the party frames takes, the Party Frames kit's flip included.
    PopFrame.KitSide = function(place)
        local before = place == "left"
        if mod.RF_PartyKit() then
            before = mod.RF_KitAttach(saved.profile, before)
        end
        return before
    end

    -- The pet group goes after Friendly Boss and Extra Frames when they sit on the same side. Beside
    -- the party frames only a Show in Dungeons boss group is attached there to follow, and Extra
    -- Frames (raid only) never is.
    PopFrame.ChainAnchor = function(pset)
        if pset.position == "free" or pset.position == "owner" then
            return
        end
        local party = PopFrame.PartyMode()
        local fontStr = FB.Settings()
        if fontStr and FB.built and FB.container:IsShown() then
            if party then
                if
                    fontStr.position ~= "free"
                    and fontStr.showInDungeons == true
                    and PopFrame.KitSide(fontStr.position) == PopFrame.KitSide(pset.position)
                then
                    return FB.container
                end
            elseif fontStr.position == pset.position then
                return FB.container
            end
        end
        if party then
            return
        end
        local xf = mod._XF
        local xs = xf.Settings()
        if xs and xs.position == pset.position and xf.built and xf.container and xf.container:IsShown() then
            return xf.container
        end
    end

    -- map: the unit -> button map the button keeps itself in (none for your own Beside Owner pet).
    PopFrame.StyleButton = function(b, map)
        b:RegisterForClicks("AnyUp")
        b:SetAttribute("*type1", "target")
        -- The engine gates SecureUnitButton's togglemenu; route right-click through a SecureActionButton proxy so the menu works without taint.
        CludesUI.AttachSecureUnitMenu(b)
        FB.BuildVisuals(b, true)

        b:HookScript("OnShow", function(self)
            PopFrame.visCount = (PopFrame.visCount or 0) + 1
            -- A button showing again holds its unit's map entry, which another button may have taken
            -- and dropped while this one was off screen with the same unit.
            if map then
                local u = self:GetAttribute("unit")
                local d = GetFFD(self)
                local old = d.pfUnit
                if old and old ~= u and map[old] == self then
                    map[old] = nil
                end
                if u then
                    map[u] = self
                end
                d.pfUnit = u
            end
            -- Header buttons hidden at the last restyle catch up as they show.
            local g = PopFrame.styledGen[self]
            if g and g ~= PopFrame.styleGen then
                PopFrame.StyleHeaderButton(self)
            end
            PopFrame.Refresh(self)
            PopFrame.SyncShownEvents()
        end)
        b:HookScript("OnHide", function(self)
            PopFrame.visCount = math.max(0, (PopFrame.visCount or 0) - 1)
            local d = GetFFD(self)
            d.pfPaintUnit, d.pfGuid = nil, nil
            PopFrame.SyncShownEvents()
        end)
        b:HookScript("OnEnter", function(self)
            FB.hov[self] = true
            FB.ApplyBorderColor(self)
        end)
        b:HookScript("OnLeave", function(self)
            FB.hov[self] = nil
            FB.ApplyBorderColor(self)
        end)
        -- The header (or, beside the party frames, the party frame's unit snippet) re-units buttons as
        -- pets come and go, in combat too. Both re-set every button's unit on each re-process (roster,
        -- name and pet events), so most fires re-confirm the pet already painted: those keep only the
        -- map write. A hidden button paints as it shows.
        b:HookScript("OnAttributeChanged", function(self, name, value)
            if name ~= "unit" then
                return
            end
            local d = GetFFD(self)
            if map then
                local old = d.pfUnit
                if old and map[old] == self then
                    map[old] = nil
                end
                if value then
                    map[value] = self
                end
                d.pfUnit = value
            end
            if not value or not self:IsVisible() then
                d.pfPaintUnit, d.pfGuid = nil, nil
                if not value then
                    FB.tgt[self] = nil
                end
                return
            end
            if value == d.pfPaintUnit then
                local g = UnitGUID(value)
                if issecretvalue(g) then
                    g = nil
                end
                if g and g == d.pfGuid then
                    return
                end
            end
            PopFrame.Refresh(self)
        end)

        -- Full click-cast / hovercast binding suite (mouseover heals included)
        if mod.CC_RegisterFrame then
            mod.CC_RegisterFrame(b)
        end
    end

    -- One header button at the header's current size and style.
    PopFrame.StyleHeaderButton = function(b)
        if not PopFrame.w then
            return
        end
        local s = PopFrame.StyleSource()
        FB.StyleVisuals(
            b,
            s,
            PopFrame.w,
            PopFrame.h,
            ResolveHealthTexture(s),
            s.customBgColor or PopFrame.DEFAULT_BG
        )
        PopFrame.styledGen[b] = PopFrame.styleGen
    end

    -- Every setting the button styler reads (FB.StyleVisuals with FB.StyleBorder; the size is checked on
    -- its own), plus the UI scale its pixel-sized borders follow, gathered into a reused list, so a
    -- reload that changed none of them leaves the pets' fonts, textures and borders alone. The hover and
    -- target borders are painted, not styled.
    PopFrame.STYLE_N = 26 + mod.RF_TEXT_STYLE_N
    PopFrame.fp = {}
    PopFrame.fpNew = {}
    PopFrame.StyleInputs = function(t, s, texPath)
        local bgc = s.customBgColor or PopFrame.DEFAULT_BG
        local bc = s.borderColor
        t[1], t[2], t[3], t[4], t[5] = bgc.r, bgc.g, bgc.b, s.bgDarkness, texPath
        t[6], t[7] = s.healthVerticalFill, s.healthBarOpacity
        t[8], t[9] = CludesUI.GetFontPath("raidFrames"), CludesUI.GetFontOutlineFlag("raidFrames")
        t[10], t[11], t[12], t[13], t[14] = s.borderSize, bc and bc.r, bc and bc.g, bc and bc.b, s.borderAlpha
        t[15], t[16], t[17] = s.borderTexture, s.borderSizePx, s.borderBehind
        t[18], t[19] = s.borderTextureOffset, s.borderTextureOffsetY
        t[20], t[21] = s.borderTextureShiftX, s.borderTextureShiftY
        t[22] = UIParent:GetEffectiveScale()
        t[23] = s.healthInvertFill
        t[24], t[25] = s.cornerRadius, s.cornerMask
        -- The texts: the plan signature, then offsets and size of each (t[26] on).
        mod.RF_TextStyleInputs(t, 25, s)
        t[PopFrame.STYLE_N] = s.textureBg -- Textured Background
    end

    -- True when the inputs differ from the ones last styled under key ("hdr": the header, "owner": the
    -- Beside Owner pets, "pt": the party target frames), which they then become (two lists trade
    -- places, nothing allocated). extra(t), when given, writes the key's own inputs after the shared
    -- ones, n slots in all (the party target frames' colour settings). The second return is the first
    -- slot that differs (0 with nothing styled yet), so a key with extra slots can tell a change to
    -- its own inputs alone (past PF.STYLE_N) from one the styler reads.
    PopFrame.StyleChanged = function(key, s, texPath, extra, num)
        local new = PopFrame.fpNew
        PopFrame.StyleInputs(new, s, texPath)
        if extra then
            extra(new)
        end
        local old, at = PopFrame.fp[key], 0
        if old then
            for idx = 1, num or PopFrame.STYLE_N do
                if old[idx] ~= new[idx] then
                    at = idx
                    break
                end
            end
            if at == 0 then
                return false
            end
        end
        PopFrame.fp[key] = new
        PopFrame.fpNew = old or {}
        return true, at
    end

    PopFrame.CompactStyleInput = function(t)
        t[PopFrame.STYLE_N + 1] = mod.RF_CompactOn(PopFrame.StyleSource(), PopFrame.styleCtx == "party")
    end

    -- Header buttons: five in one column beside the party frames, all forty (eight columns) once raid
    -- pets are on. The column count caps what the header shows, so it never makes a button itself.
    PopFrame.Capacity = function()
        local raw = PopFrame.Raw()
        return (raw and raw.raid == true) and PopFrame.MAX or 5
    end

    -- A header makes children only while visible, so the buttons up to the capacity are made up front
    -- (the raid headers' startingIndex pass, its parent shown for it) and set up once; the header then
    -- assigns pets to them. The pass leaves the header hidden for the apply to show laid out. With the
    -- UI hidden (a cinematic, Alt-Z) nothing is made and the next apply tries again. OOC only.
    PopFrame.EnsureBuilt = function()
        local cap = PopFrame.Capacity()
        local have = #PopFrame.buttons
        if have >= cap then
            return true
        end
        local heading = PopFrame.container
        if not heading then
            -- The header's parent carries its pet-battle and solo hide (see PF.SetHider).
            local hider = CreateFrame("Frame", nil, UIParent)
            hider:SetAllPoints(UIParent)
            PopFrame.hider = hider
            heading = CreateFrame("Frame", "ERFPetHeader", hider, "SecureGroupPetHeaderTemplate")
            heading:SetAttribute("template", "SecureUnitButtonTemplate")
            heading:SetAttribute("templateType", "Button")
            heading:SetAttribute("showRaid", true)
            heading:SetAttribute("showParty", true)
            heading:SetAttribute("showPlayer", true)
            heading:SetAttribute("sortMethod", "INDEX")
            heading:SetAttribute("unitsPerColumn", 5)
            -- The forty-button pass lays its buttons out in columns, which needs a column anchor;
            -- PF.Layout sets the real one.
            heading:SetAttribute("columnAnchorPoint", "LEFT")
            PopFrame.container = heading
            -- Switched on with a preview up: dim it like the other real frames.
            if mod._raidPvActive or mod._partyPvActive then
                mod._SetRealFramesPreviewHidden(true)
            end
        end
        if not heading[cap] then
            local hider = PopFrame.hider
            local hid = not hider:IsShown()
            heading:Hide()
            if hid then
                hider:Show()
            end
            heading:SetAttribute("maxColumns", cap > 5 and 8 or 1)
            heading:SetAttribute("startingIndex", 1 - cap)
            heading:Show()
            heading:SetAttribute("startingIndex", 1)
            heading:Hide()
            if hid then
                hider:Hide()
            end
        end
        for idx = have + 1, cap do
            local b = heading[idx]
            if not b then
                break
            end
            GetFFD(b)._petHeader = true
            PopFrame.StyleButton(b, PopFrame.byUnit)
            FB.src[b] = PopFrame.StyleSource
            PopFrame.styledGen[b] = 0
            PopFrame.buttons[idx] = b
        end
        local num = #PopFrame.buttons
        if num == 0 then
            return false
        end
        -- New buttons take their size on the next layout.
        if num > have then
            PopFrame.w = nil
        end
        PopFrame.EnsureTrackers(num >= PopFrame.MAX and PopFrame.ALL_TRACKERS or PopFrame.SMALL_TRACKERS)
        PopFrame.built = true
        return true
    end

    -- Per-event slices of the full paint (PF.Refresh): health events repaint the health value and texts,
    -- name events the name, range updates the range fade.
    PopFrame.PaintHealth = function(b, u)
        if UnitExists(u) then
            FB.PaintHealth(b, u, FB.Source(b))
        end
    end
    PopFrame.PaintName = function(b, u)
        if UnitExists(u) then
            FB.PaintName(b, u, FB.Source(b))
        end
    end

    -- The event's pet is on the header button holding it, and beside the party frames on its Beside
    -- Owner pet (your pet on your own pet button or on the party frame showing you: one of them shows).
    PopFrame.OnTrackerEvent = function(_, evt, u)
        local paint = PopFrame.PaintHealth
        if evt == "UNIT_IN_RANGE_UPDATE" then
            paint = PopFrame.ApplyRange
        elseif evt == "UNIT_NAME_UPDATE" then
            paint = PopFrame.PaintName
        end
        local b = PopFrame.byUnit[u]
        if b and b:IsVisible() then
            paint(b, u)
        end
        if PopFrame.ownerActive then
            b = PopFrame.ownerByUnit[u]
            if b and b:IsVisible() then
                paint(b, u)
            end
            b = PopFrame.selfPet
            if u == "pet" and b:IsVisible() then
                paint(b, u)
            end
        end
    end

    -- Up to n tracker frames, two pet tokens each (RegisterUnitEvent takes two units), from the shell
    -- pool. Frames added while pets are on screen listen at once (the listeners switch on edges).
    PopFrame.EnsureTrackers = function(num)
        for k = #PopFrame.trackers + 1, num do
            local idx = 2 * k - 1
            local t = mod.TakeShell()
            t:SetScript("OnEvent", PopFrame.OnTrackerEvent)
            local tr = { frame = t, u1 = PopFrame.UNITS[idx], u2 = PopFrame.UNITS[idx + 1] }
            PopFrame.trackers[k] = tr
            if PopFrame.shownEv then
                PopFrame.TrackerEvents(tr, true)
            end
        end
    end

    -------------------------------------------------------------------------------
    --  Beside Owner (Party tab): a pet button beside each party frame. The party
    --  header's children carry them as children, so they follow every re-sort and
    --  hide with their frame (Hide Self included). Each party frame's unit snippet
    --  (refreshUnitChange, run by the header right after it assigns the frame's
    --  unit, in combat too) writes the pet's own unit, so mouseover, click-cast
    --  and the target and menu proxies see the pet token itself. It writes on
    --  every pass, the same token included: tokens are positional, so a member
    --  leaving hands a frame's token to the next member, and the pet's unit hook
    --  then re-checks the occupant. Your own pet has a button of its own on the
    --  party container: beside the self button, or with Hide Self in your frame's
    --  empty slot after the last party frame.
    --  The same snippet carries the party target frames' Include Own Target gate:
    --  with it off (pt-noself), the frame holding you drops its target frame's
    --  unit (the restricted environment has no UnitIsUnit, so your raid token is
    --  compared as pt-me). The pet part runs only while the pets are up (pf-on).
    --  Limitation: pt-me is written out of combat. A raid index shift in combat
    --  (arena, Small Raid: a lower-index member leaves) leaves it stale until the
    --  combat-end reseed (ns._ptSelfDirty -> ns._PT_SyncSelf): your own target
    --  shows, and the member now on your old token loses theirs, until then.
    -------------------------------------------------------------------------------
    PopFrame.OWNER_SNIPPET = [[
    local u = self:GetAttribute("unit")
    if self:GetAttribute("pf-on") then
        local pu
        if u == "player" then
            pu = "pet"
        elseif u then
            local k, n = strmatch(u, "^(%a+)(%d+)$")
            if k then pu = k .. "pet" .. n end
        end
        local pet = self:GetFrameRef("pfpet")
        if pet then pet:SetAttribute("unit", pu) end
        local sp = self:GetFrameRef("pfself")
        if sp and sp:GetAttribute("pf-hs") then
            sp:ClearAllPoints()
            sp:SetPoint(sp:GetAttribute("pf-pt"), self, sp:GetAttribute("pf-rp"), sp:GetAttribute("pf-x"), sp:GetAttribute("pf-y"))
        end
    end
    local pt = self:GetFrameRef("ptframe")
    if pt then
        local show = not (pt:GetAttribute("pt-noself") and u and (u == "player" or u == pt:GetAttribute("pt-me")))
        if pt:GetAttribute("useparent-unit") ~= show then pt:SetAttribute("useparent-unit", show) end
    end
]]

    -- OOC only.
    PopFrame.EnsureOwnerBuilt = function()
        if PopFrame.ownerBuilt then
            return
        end
        PopFrame.ownerBuilt = true
        -- Your pet hangs off the container, not the self button, so it can outlive Hide Self.
        local sp = CreateFrame("Button", nil, mod._partyContainerFrame, "SecureUnitButtonTemplate")
        sp:SetAttribute("unit", "pet")
        sp:Hide()
        PopFrame.StyleButton(sp)
        FB.src[sp] = PopFrame.PartySource
        PopFrame.selfPet = sp
        PopFrame.ownerButtons[1] = sp
        for _, ownerFrame in ipairs(mod._partyAllButtons) do
            if ownerFrame ~= mod._partySelfButton then
                local b = CreateFrame("Button", nil, ownerFrame, "SecureUnitButtonTemplate")
                b:Hide()
                b:SetIgnoreParentAlpha(true)
                PopFrame.ownerOf[b] = ownerFrame
                PopFrame.StyleButton(b, PopFrame.ownerByUnit)
                FB.src[b] = PopFrame.PartySource
                PopFrame.ownerButtons[#PopFrame.ownerButtons + 1] = b
                SecureHandlerSetFrameRef(ownerFrame, "pfpet", b)
                SecureHandlerSetFrameRef(ownerFrame, "pfself", sp)
            end
        end
        PopFrame.EnsureTrackers(PopFrame.SMALL_TRACKERS)
    end

    -- The party frames' one unit snippet, installed while the Beside Owner pets or the party target
    -- frames' Include Own Target gate (ns._ptNoSelf) need it, with the pet part switched by pf-on.
    -- Only changed attributes are written. OOC only.
    PopFrame.SyncUnitSnippet = function()
        local pets = PopFrame.ownerActive and true or nil
        local code = (pets or mod._ptNoSelf) and PopFrame.OWNER_SNIPPET or nil
        for _, o in ipairs(mod._partyAllButtons) do
            if o ~= mod._partySelfButton then
                if o:GetAttribute("pf-on") ~= pets then
                    o:SetAttribute("pf-on", pets)
                end
                if o:GetAttribute("refreshUnitChange") ~= code then
                    o:SetAttribute("refreshUnitChange", code)
                end
            end
        end
    end
    mod.PF_SyncUnitSnippet = PopFrame.SyncUnitSnippet

    -- Switches the snippet's pet part on or off; on, seeds each pet's unit from its frame's current one
    -- (written as the snippet does, the same token included). OOC only.
    PopFrame.SetOwnerLinks = function(enabled)
        if enabled then
            for _, b in ipairs(PopFrame.ownerButtons) do
                local o = PopFrame.ownerOf[b]
                if o then
                    local u = o:GetAttribute("unit")
                    b:SetAttribute("unit", u and PopFrame.PET_OF[u])
                end
            end
        end
        PopFrame.SyncUnitSnippet()
    end

    -- Unit watches on the Beside Owner pets run only while the party frames are on screen. OOC only.
    PopFrame.SetOwnerWatch = function()
        local wanted = (PopFrame.ownerActive and mod._partyContainerFrame:IsShown()) and true or false
        if PopFrame.watching ~= wanted then
            PopFrame.watching = wanted
            for _, b in ipairs(PopFrame.ownerButtons) do
                if PopFrame.ownerOf[b] then
                    if wanted then
                        RegisterUnitWatch(b)
                    else
                        UnregisterUnitWatch(b)
                        b:Hide()
                    end
                end
            end
        end
        PopFrame.PlaceSelfPet()
    end

    -- Party frame size (the raid frame size under the Party Frames layout, whose size is its portrait
    -- box, as Friendly Boss does).
    PopFrame.PartySize = function(s)
        local wid, hgt, sp = mod.RF_PartyDims(saved.profile)
        if mod.RF_PartyKit() then
            wid, hgt, sp = s.frameWidth or 125, s.frameHeight or 60, s.cellSpacing or -1
        end
        return wid, hgt, sp
    end

    -- A tab's pet size (its frames' size plus that tab's Extra Width/Height), spacing and growth: the
    -- party frames' size and stacking on the Party tab, the raid frame size and growth on the Raid tab.
    -- Free Move takes the tab's Growth Direction when one is set, its columns turned across it.
    PopFrame.Geometry = function(context)
        local s = mod._scaledProfile or saved.profile
        local wid, hgt, sp, unitGrowth, groupGrowth
        if context == "party" then
            wid, hgt, sp = PopFrame.PartySize(s)
            unitGrowth = mod._PartyGrowth(saved.profile)
            groupGrowth = (unitGrowth == "RIGHT" or unitGrowth == "LEFT") and "DOWN" or "RIGHT"
        else
            wid, hgt, sp = s.frameWidth or 125, s.frameHeight or 60, s.cellSpacing or -1
            unitGrowth, groupGrowth =
                mod._RFEffectiveGrowth(s.unitGrowth or "DOWN", s.groupGrowth or "RIGHT", true)
        end
        if mod.RF_CompactOn(context == "party" and mod._partyProxy or s, context == "party") then
            sp = mod.RF_OnePixel(context == "party")
        end
        local v = PopFrame.View(context)
        local fg = v.position == "free" and v.freeGrowth
        if fg then
            unitGrowth = fg
            if mod._RFGrowthIsVertical(fg) == mod._RFGrowthIsVertical(groupGrowth) then
                groupGrowth = mod._RFGrowthIsVertical(fg) and "RIGHT" or "DOWN"
            end
        end
        wid = PixelSnap(math.max(10, wid + (v.extraWidth or 0)))
        hgt = PixelSnap(math.max(10, hgt + (v.extraHeight or 0)))
        -- Same grid as FB.FreePin: the pet header's own scale.
        sp = CludesUI.PP.SnapForES(sp, (PopFrame.container or UIParent):GetEffectiveScale())
        return wid, hgt, sp, unitGrowth, groupGrowth
    end

    -- Pet Side, fitted to the party frames' orientation: across the stack only (Left/Right beside
    -- stacked frames, Above/Below horizontal ones), so a pet never lands on the next frame. A choice
    -- that no longer fits reads as the default until it fits again. s: the profile (or preview view).
    PopFrame.OwnerSide = function(s)
        local raw = PopFrame.Raw()
        local sideName = raw and raw.ownerSide
        if s.partyHorizontal then
            if sideName ~= "above" and sideName ~= "below" then
                sideName = "below"
            end
        elseif sideName ~= "left" and sideName ~= "right" then
            sideName = "right"
        end
        return sideName
    end
    function mod.PF_OwnerSide()
        return PopFrame.OwnerSide(saved.profile)
    end

    -- The side the pets take and the extra gap: the Party Frames kit moves them off its outside auras
    -- as it does the Friendly Boss group.
    PopFrame.ResolveOwnerSide = function(s)
        local sideName = PopFrame.OwnerSide(s)
        local extra = 0
        if mod.RF_PartyKit() then
            local before = sideName == "left" or sideName == "above"
            before, extra = mod.RF_KitAttach(s, before)
            if s.partyHorizontal then
                sideName = before and "above" or "below"
            else
                sideName = before and "left" or "right"
            end
        end
        return sideName, extra
    end

    PopFrame.OwnerPoint = function(b, ownerFrame, sideName, gap)
        if sideName == "left" then
            b:SetPoint("TOPRIGHT", ownerFrame, "TOPLEFT", -gap, 0)
        elseif sideName == "below" then
            b:SetPoint("TOPLEFT", ownerFrame, "BOTTOMLEFT", 0, -gap)
        elseif sideName == "above" then
            b:SetPoint("BOTTOMLEFT", ownerFrame, "TOPLEFT", 0, gap)
        else
            b:SetPoint("TOPLEFT", ownerFrame, "TOPRIGHT", gap, 0)
        end
    end

    -- Size, side and style of the Beside Owner pets: only what changed is touched (the party layout pass
    -- runs this on every roster edge). restyle (a settings reload) checks the style inputs, and restyles
    -- the fonts, textures and borders only when they changed; a size change alone resizes. OOC only.
    PopFrame.OwnerLayout = function(restyle)
        local wid, hgt, sp = PopFrame.Geometry("party")
        local sideName, extra = PopFrame.ResolveOwnerSide(saved.profile)
        local baseGap = PixelSnap(sp)
        local gap = baseGap + PixelSnap(extra)
        local resized = wid ~= PopFrame.ownerW or hgt ~= PopFrame.ownerH
        local moved = sideName ~= PopFrame.ownerSideCur or gap ~= PopFrame.ownerGap
        PopFrame.ownerW, PopFrame.ownerH, PopFrame.ownerSideCur, PopFrame.ownerGap, PopFrame.ownerBaseGap =
            wid, hgt, sideName, gap, baseGap
        local s, texPath
        local restyled = false
        if restyle then
            s = PopFrame.PartySource()
            texPath = ResolveHealthTexture(s)
            restyled = PopFrame.StyleChanged("owner", s, texPath)
        end
        if restyled then
            local bgc = s.customBgColor or PopFrame.DEFAULT_BG
            for _, b in ipairs(PopFrame.ownerButtons) do
                b:SetSize(wid, hgt)
                FB.StyleVisuals(b, s, wid, hgt, texPath, bgc)
            end
        elseif resized then
            for _, b in ipairs(PopFrame.ownerButtons) do
                b:SetSize(wid, hgt)
                FB.SizeVisuals(b, wid, hgt)
            end
        end
        if moved then
            for _, b in ipairs(PopFrame.ownerButtons) do
                local o = PopFrame.ownerOf[b]
                if o then
                    b:ClearAllPoints()
                    PopFrame.OwnerPoint(b, o, sideName, gap)
                end
            end
        end
        if resized or moved then
            PopFrame.PlaceSelfPet(true)
            PopFrame.NotifyReserve()
        end
    end

    -- Your own pet: beside the self button while that shows you. With Hide Self (in a group), in your
    -- frame's empty slot after the last party frame: seated here, then re-seated by the party frames'
    -- unit snippet after whichever frame the header fills last, so joins, leaves and re-sorts in combat
    -- carry it along. While the party header shows you, that frame's own pet has it and this one stays
    -- hidden. Repeat calls with nothing changed return at once. OOC only.
    PopFrame.PlaceSelfPet = function(force)
        local b = PopFrame.selfPet
        if not b then
            return
        end
        if InCombatLockdown() then
            PopFrame.anchorDirty = true
            return
        end
        local modeName = "off"
        if PopFrame.watching then
            local m = mod._partySelfMode
            if m == "button" or (m == "hidden" and IsInGroup()) then
                modeName = m
            end
        end
        if modeName == "off" then
            if force or PopFrame.spMode ~= "off" then
                PopFrame.spMode = "off"
                b:SetAttribute("pf-hs", nil)
                UnregisterUnitWatch(b)
                b:Hide()
            end
            return
        end
        local grow = mod._PartyGrowth(saved.profile)
        local _, _, psp = mod.RF_PartyDims(saved.profile)
        -- The party frames' pitch: spacing, plus the room party target frames along the stack take.
        local slotGap = PixelSnap(psp) + mod.PT_AlongPitch(saved.profile)
        if
            not force
            and modeName == PopFrame.spMode
            and PopFrame.ownerSideCur == PopFrame.spSide
            and PopFrame.ownerGap == PopFrame.spGap
            and grow == PopFrame.spGrow
            and slotGap == PopFrame.spSlotGap
        then
            return
        end
        PopFrame.spMode, PopFrame.spSide, PopFrame.spGap, PopFrame.spGrow, PopFrame.spSlotGap =
            modeName, PopFrame.ownerSideCur, PopFrame.ownerGap, grow, slotGap
        if modeName == "hidden" then
            local pt, rp, posX, posY, baseValue
            if grow == "UP" then
                pt, rp, posX, posY, baseValue = "BOTTOMLEFT", "TOPLEFT", 0, slotGap, "BOTTOMLEFT"
            elseif grow == "RIGHT" then
                pt, rp, posX, posY, baseValue = "TOPLEFT", "TOPRIGHT", slotGap, 0, "TOPLEFT"
            elseif grow == "LEFT" then
                pt, rp, posX, posY, baseValue = "TOPRIGHT", "TOPLEFT", -slotGap, 0, "TOPRIGHT"
            else
                pt, rp, posX, posY, baseValue = "TOPLEFT", "BOTTOMLEFT", 0, -slotGap, "TOPLEFT"
            end
            b:SetAttribute("pf-pt", pt)
            b:SetAttribute("pf-rp", rp)
            b:SetAttribute("pf-x", posX)
            b:SetAttribute("pf-y", posY)
            b:SetAttribute("pf-hs", true)
            local heading = mod._partyHeader
            local last
            for idx = 1, 5 do
                local c = heading[idx]
                if c and c:IsShown() and c:GetAttribute("unit") then
                    last = c
                end
            end
            b:ClearAllPoints()
            if last then
                b:SetPoint(pt, last, rp, posX, posY)
            else
                b:SetPoint(baseValue, heading, baseValue, 0, 0)
            end
        else
            b:SetAttribute("pf-hs", nil)
            b:ClearAllPoints()
            PopFrame.OwnerPoint(b, mod._partySelfButton, PopFrame.ownerSideCur, PopFrame.ownerGap)
        end
        RegisterUnitWatch(b)
    end

    -- A Show in Dungeons boss group beside the party frames clears the Beside Owner pets' column, and
    -- the party target frames follow the pets on their side.
    PopFrame.NotifyReserve = function()
        mod._PT_Layout()
        local fontStr = FB.Settings()
        if FB.built and fontStr and fontStr.showInDungeons == true then
            FB.Anchor()
        end
    end

    -- The room the Beside Owner pets take on the side a group attaches to the party frames (horizontal:
    -- the party frames' orientation; before: left, or above horizontal frames).
    function mod.PF_OwnerReserve(horizontal, before)
        local sideName = PopFrame.ownerActive and PopFrame.ownerSideCur
        if not sideName then
            return 0
        end
        if horizontal then
            if (before and sideName == "above") or (not before and sideName == "below") then
                return PopFrame.ownerH + PopFrame.ownerBaseGap
            end
        elseif (before and sideName == "left") or (not before and sideName == "right") then
            return PopFrame.ownerW + PopFrame.ownerBaseGap
        end
        return 0
    end

    -- Whether either kind of pet is up. Its listeners follow the pets on screen (PF.SyncShownEvents),
    -- the vehicle edges among them: an owner entering or leaving a vehicle swaps what its pet token
    -- stands for without touching any unit attribute (PF.OnPetChanged re-checks that owner's pet).
    PopFrame.SetTracking = function(enabled)
        if PopFrame.tracking == enabled then
            return
        end
        PopFrame.tracking = enabled
        PopFrame.SyncShownEvents()
    end

    -- One write of a batch on the header: the batch's first change sets _ignore, so the header skips its
    -- update per attribute; the caller clears it and re-runs the header once. changed: whether the
    -- batch has changed anything yet; returns the same for after this write.
    local function SetAttr(heading, key, value, changed)
        if heading:GetAttribute(key) == value then
            return changed
        end
        if not changed then
            heading:SetAttribute("_ignore", "attributeChanges")
        end
        heading:SetAttribute(key, value)
        return true
    end

    -- The pet header's parent hides it in pet battles and, unless your pet shows solo, outside a group.
    -- A visibility driver writes the statehidden attribute on its frame every 0.2 s; on the header that
    -- attribute change re-runs its whole update, so the driver sits on this plain parent. Re-registered
    -- only when the macro changes. Grouped = a raid1/party1 unit exists, which stays live in combat
    -- (see ns._RF_VIS_MACROS).
    -- solo: the header's showSolo. OOC only.
    PopFrame.SetHider = function(solo)
        local m = solo and "[petbattle] hide; show"
            or "[petbattle] hide; [@raid1,exists][@party1,exists][group] show; hide"
        if PopFrame.hiderMacro ~= m then
            RegisterStateDriver(PopFrame.hider, "visibility", m)
            PopFrame.hiderMacro = m
        end
    end

    -- Teardown, after the header is hidden: the driver goes and the parent shows again, so a later build
    -- makes its buttons under a shown parent. OOC only.
    PopFrame.ClearHider = function()
        if not PopFrame.hiderMacro then
            return
        end
        UnregisterStateDriver(PopFrame.hider, "visibility")
        PopFrame.hiderMacro = nil
        PopFrame.hider:Show()
    end

    -- Show Groups as a groupFilter: nil with every group on, one cached string per group set.
    PopFrame.gf = {}
    PopFrame.RaidGroupFilter = function()
        local vg = mod._VisibleGroups() -- Mythic 5-8 aware (read-only)
        if not vg then
            return nil
        end
        local maskTex = 0
        for gi = 1, 8 do
            if vg[gi] ~= false then
                maskTex = maskTex + 2 ^ (gi - 1)
            end
        end
        if maskTex == 255 then
            return nil
        end
        local str = PopFrame.gf[maskTex]
        if not str then
            str = ""
            for gi = 1, 8 do
                if vg[gi] ~= false then
                    str = (str == "") and tostring(gi) or (str .. "," .. gi)
                end
            end
            PopFrame.gf[maskTex] = str
        end
        return str
    end

    -- Size and growth follow the frames on screen (the party frames' in party mode, else the raid
    -- frames'), plus that tab's size offsets. Roster edges come through here too, so only what changed
    -- is touched: restyle (a settings or profile reload) and a party/raid flip restyle only when the
    -- style inputs changed, a size change alone resizes, and buttons off screen catch up as they show.
    -- Both also repaint the pets on screen, whose paint reads the settings too. OOC only.
    PopFrame.Layout = function(restyle)
        local context = PopFrame.Ctx()
        local party = context == "party"
        local wid, hgt, sp, unitGrowth, groupGrowth = PopFrame.Geometry(context)
        local heading = PopFrame.container
        local resized = wid ~= PopFrame.w or hgt ~= PopFrame.h
        PopFrame.w, PopFrame.h, PopFrame.sp, PopFrame.unitGrowth, PopFrame.groupGrowth =
            wid, hgt, sp, unitGrowth, groupGrowth
        local flipped = PopFrame.styleCtx ~= context
        local restyled = false
        if restyle or flipped then
            PopFrame.styleCtx = context
            local ss = PopFrame.StyleSource()
            restyled = PopFrame.StyleChanged(
                "hdr",
                ss,
                ResolveHealthTexture(ss),
                PopFrame.CompactStyleInput,
                PopFrame.STYLE_N + 1
            )
        end
        if resized then
            for _, b in ipairs(PopFrame.buttons) do
                b:SetSize(wid, hgt)
            end
        end
        if restyled or resized then
            PopFrame.styleGen = (PopFrame.styleGen or 0) + 1
            for _, b in ipairs(PopFrame.buttons) do
                if b:IsVisible() then
                    if restyled then
                        PopFrame.StyleHeaderButton(b)
                    else
                        FB.SizeVisuals(b, wid, hgt)
                        PopFrame.styledGen[b] = PopFrame.styleGen
                    end
                end
            end
        end
        -- Before the header re-runs below: the pets it re-assigns paint in their unit hook, and the
        -- ones it shows as they show.
        if restyle or flipped then
            PopFrame.RepaintShown(PopFrame.buttons)
        end

        local s = mod._scaledProfile or saved.profile
        -- Party: Small Raid mode shows only group 1 in the party frames, and your pet shows solo while
        -- the party frames do. Raid: the groups Show Groups keeps.
        local group
        if party then
            local g = mod._SmallRaidGroup()
            group = g and tostring(g) or nil
        else
            group = PopFrame.RaidGroupFilter()
        end
        -- Beside the party frames the pets keep the party frames' pitch, which party target frames along
        -- the stack open (the kit's pets take the raid frame size, which never lines up with them).
        local pitch = sp
        if party and not mod.RF_PartyKit() and PopFrame.View("party").position ~= "free" then
            pitch = sp + mod.PT_AlongPitch(saved.profile)
        end
        local anchorPoint, xOff, yOff = mod._RFHeaderPoint(unitGrowth, pitch)
        local solo = (party and saved.profile.partyShowWhenSolo) and true or nil
        -- One batch: the header re-runs once below, not per attribute.
        local changed = SetAttr(heading, "groupFilter", group, false)
        changed = SetAttr(heading, "showSolo", solo, changed)
        changed = SetAttr(heading, "point", anchorPoint, changed)
        changed = SetAttr(heading, "xOffset", xOff, changed)
        changed = SetAttr(heading, "yOffset", yOff, changed)
        changed = SetAttr(
            heading,
            "columnSpacing",
            party and PixelSnap(s.groupSpacing or 8) or mod.RF_GroupSpacing(s),
            changed
        )
        changed = SetAttr(heading, "columnAnchorPoint", mod._RFColAnchor(unitGrowth, groupGrowth), changed)
        changed = SetAttr(heading, "maxColumns", #PopFrame.buttons >= PopFrame.MAX and 8 or 1, changed)
        if changed then
            heading:SetAttribute("_ignore", nil)
        end
        -- Blizzard never clears a shown button's anchors, and a leftover column anchor pins button 1 to
        -- the header's old size, so a new size or layout re-lays from cleared anchors (as the merged raid
        -- header does). One write of a spare attribute then re-runs the header once on the final
        -- attributes (clearing _ignore runs nothing, and a new size alone changes no attribute), with
        -- no pet hidden and re-shown. A header not on screen re-runs as it shows.
        if resized or changed then
            for _, b in ipairs(PopFrame.buttons) do
                b:ClearAllPoints()
            end
            heading:SetAttribute("pf-relayout", not heading:GetAttribute("pf-relayout"))
        end
        -- Last, so a parent that shows here runs the header once on the final attributes.
        PopFrame.SetHider(solo)
        mod.RF_SyncPetCompact()
    end

    -- Free Move: the header is pinned at the corner its pets grow from, so pet 1 stays put as pets come
    -- and go. The overlay covers five pets; until its first drag they are centred on freePos. ctx: the
    -- tab whose spot and size this is.
    PopFrame.FreeCorner = function(set, context)
        local wid, hgt, sp, unitGrowth, groupGrowth = PopFrame.Geometry(context)
        local vertical = unitGrowth ~= "RIGHT" and unitGrowth ~= "LEFT"
        local hDir = vertical and groupGrowth or unitGrowth
        local vDir = vertical and unitGrowth or groupGrowth
        if vertical then
            hgt = 5 * hgt + 4 * sp
        else
            wid = 5 * wid + 4 * sp
        end
        local r = set.freeRect
        local corner, posX, posY = FB.CornerPin(hDir, vDir, r)
        if not r then
            local p = set.freePos
            local cx, cy = p and p.x or 100, p and p.y or 0
            posX = (hDir == "LEFT") and (cx + wid / 2) or (cx - wid / 2)
            posY = (vDir == "UP") and (cy - hgt / 2) or (cy + hgt / 2)
        end
        return corner, posX, posY, wid, hgt
    end

    PopFrame.FreeAnchor = function(c, set)
        local corner, posX, posY = PopFrame.FreeCorner(set, PopFrame.Ctx())
        FB.FreePin(c, corner, posX, posY)
        return true
    end

    -- The Move Frames overlay places the spot of the tab it was opened on, which need not be the live one.
    PopFrame.MoverSettings = function()
        return PopFrame.Raw() and PopFrame.View(PopFrame.moverCtx or PopFrame.Ctx())
    end

    -- Before the overlay shows: the live header, when up, takes the current settings.
    PopFrame.MoverPrep = function()
        if PopFrame.active and not InCombatLockdown() then
            PopFrame.Layout()
            PopFrame.Anchor()
        end
    end

    PopFrame.PlaceMover = function(m, set)
        local corner, posX, posY, wid, hgt = PopFrame.FreeCorner(set, PopFrame.moverCtx or PopFrame.Ctx())
        m:SetSize(wid, hgt)
        FB.FreePin(m, corner, posX, posY)
    end

    PopFrame.SaveFreeRect = function(mover)
        FB.SaveMoverRect(mover, PopFrame.MoverSettings())
    end

    -- ctx: "party" or "raid", the tab the overlay is for (the live one when nil).
    function mod.PF_SetMoverShown(show, context)
        if show then
            PopFrame.moverCtx = context or PopFrame.Ctx()
        end
        FB.SetMoverShown(PopFrame, show, "ERFPetFramesMover", "Pet Frames")
    end

    -- ctx: true only when the overlay is up for that tab (any tab when nil).
    function mod.PF_IsMoverShown(context)
        return (
            PopFrame.mover
            and PopFrame.mover:IsShown()
            and (context == nil or PopFrame.moverCtx == context)
        ) or false
    end

    -- A size change on the tab whose overlay is up: the overlay takes the new size (the apply before
    -- this has already re-laid the live group).
    function mod.PF_PlaceMover(context)
        local m = PopFrame.mover
        if not (m and m:IsShown() and PopFrame.moverCtx == context) then
            return
        end
        local set = PopFrame.MoverSettings()
        if not set then
            return
        end
        m:ClearAllPoints()
        PopFrame.PlaceMover(m, set)
    end

    -- Options preview: made-up pets beside the preview frames, on the same visuals. Plain frames, built
    -- the first time a preview shows with Show Pets on; the preview code makes room and places them.
    PopFrame.PV_PETS = {
        { name = "Felhunter", hp = 100 },
        { name = "Ghoul", hp = 64 },
        { name = "Spirit Beast", hp = 100 },
        { name = "Water Elemental", hp = 38 },
        { name = "Imp", hp = 85 },
    }
    PopFrame.OPPOSITE = { RIGHT = "LEFT", LEFT = "RIGHT", DOWN = "UP", UP = "DOWN" }
    PopFrame.pv = {}

    -- The settings the preview pets are painted with (their border reads it through FB.Source).
    PopFrame.PvStyle = function()
        return PopFrame.pvStyle
    end

    -- One preview pass's shared paint values (reused table). The texts are the frame's texts (no
    -- class for pets: a class colour mode reads white).
    PopFrame.pvc = {}
    PopFrame.PvColors = function(s)
        local c = PopFrame.pvc
        PopFrame.pvStyle = s
        c.texPath = ResolveHealthTexture(s)
        c.bgc = s.customBgColor or PopFrame.DEFAULT_BG
        local raw = PopFrame.Raw()
        c.hc = raw and raw.healthColor
        c.opacity = (s.healthBarOpacity or 100) / 100
        return c
    end

    -- Preview pet i at w x h, styled and painted (the caller places it).
    PopFrame.PvFrame = function(idx, hostFrame, s, wid, hgt, c, grouped)
        local f = PopFrame.pv[idx]
        if not f then
            f = CreateFrame("Frame", nil, hostFrame)
            FB.BuildVisuals(f, true)
            FB.src[f] = PopFrame.PvStyle
            PopFrame.pv[idx] = f
        elseif f:GetParent() ~= hostFrame then
            f:SetParent(hostFrame)
        end
        f:SetFrameStrata(hostFrame == UIParent and "HIGH" or hostFrame:GetFrameStrata())
        f:SetSize(wid, hgt)
        local d = Inner.FFD[f]
        if grouped and mod.RF_CompactOn(s, mod._partyPvActive == true) then
            d = GetFFD(f)
            d._petGroupedPreview, d._petPreviewParty = true, mod._partyPvActive == true
        elseif d then
            d._petGroupedPreview = nil
        end
        FB.StyleVisuals(f, s, wid, hgt, c.texPath, c.bgc)

        local pet = PopFrame.PV_PETS[idx]
        local pct = pet.hp
        local hc = c.hc
        f._health:SetMinMaxValues(0, 100)
        -- pet.hp is a made-up plain number (PF.PV_PETS), so it is flipped here for an
        -- inverted fill (the _cuiInv stamp FB.StyleVisuals just left).
        f._health:SetValue(f._health._cuiInv and (100 - pct) or pct)
        f._health:SetStatusBarColor(
            hc and hc.r or 23 / 255,
            hc and hc.g or 172 / 255,
            hc and hc.b or 49 / 255,
            c.opacity
        )
        -- The texts with the boss/pet rules: made-up health (3000 per percent) and a heal absorb
        -- of a quarter of it, in the raid preview's proportions.
        local st = FB.txs[f]
        local pv = st._txPv or {}
        pv.hpPct, pv.hpPer, pv.ha, pv.name = pct, 3000, pct * 750, mod.CapName(pet.name, s)
        mod.RF_TextPreview(st, s, pv)
        f:Show()
        return f
    end

    -- Beside Owner preview: the pet size, side and gap as the real pets take them, the room it needs
    -- around the party frames (pads), and with Hide Self the slot after the last frame (sp: the party
    -- frames' spacing). s: the preview's view; w, h, sp: its party frame size and spacing.
    PopFrame.OwnerPreviewSpec = function(s, wid, hgt, sp)
        local pw, ph, gap = wid, hgt, sp
        if mod.RF_PartyKit() then
            pw, ph, gap =
                PixelSnap(s.frameWidth or 125), PixelSnap(s.frameHeight or 60), PixelSnap(s.cellSpacing or -1)
        end
        local v = PopFrame.View("party")
        pw = PixelSnap(math.max(10, pw + (v.extraWidth or 0)))
        ph = PixelSnap(math.max(10, ph + (v.extraHeight or 0)))
        local sideName, extra = PopFrame.ResolveOwnerSide(s)
        gap = gap + PixelSnap(extra)
        local upper = math.max
        local specInfo = {
            owner = true,
            w = pw,
            h = ph,
            side = sideName,
            gap = gap,
            padL = 0,
            padT = 0,
            padR = 0,
            padB = 0,
        }
        if sideName == "right" then
            specInfo.padR, specInfo.padB = gap + pw, upper(0, ph - hgt)
        elseif sideName == "left" then
            specInfo.padL, specInfo.padB = gap + pw, upper(0, ph - hgt)
        elseif sideName == "below" then
            specInfo.padB, specInfo.padR = gap + ph, upper(0, pw - wid)
        else
            specInfo.padT, specInfo.padR = gap + ph, upper(0, pw - wid)
        end
        if s.partyHideSelf then
            local grow = mod._PartyGrowth(s)
            specInfo.selfSlot = true
            -- The next slot: the party frames' pitch, party target frames along the stack included.
            sp = sp + mod.PT_AlongPitch(s, s.partyShowTargets == true)
            if grow == "UP" then
                specInfo.sPt, specInfo.sRp, specInfo.sX, specInfo.sY = "BOTTOMLEFT", "TOPLEFT", 0, sp
                specInfo.padT, specInfo.padR = upper(specInfo.padT, sp + ph), upper(specInfo.padR, pw - wid)
            elseif grow == "RIGHT" then
                specInfo.sPt, specInfo.sRp, specInfo.sX, specInfo.sY = "TOPLEFT", "TOPRIGHT", sp, 0
                specInfo.padR, specInfo.padB = upper(specInfo.padR, sp + pw), upper(specInfo.padB, ph - hgt)
            elseif grow == "LEFT" then
                specInfo.sPt, specInfo.sRp, specInfo.sX, specInfo.sY = "TOPRIGHT", "TOPLEFT", -sp, 0
                specInfo.padL, specInfo.padB = upper(specInfo.padL, sp + pw), upper(specInfo.padB, ph - hgt)
            else
                specInfo.sPt, specInfo.sRp, specInfo.sX, specInfo.sY = "TOPLEFT", "BOTTOMLEFT", 0, -sp
                specInfo.padB, specInfo.padR = upper(specInfo.padB, sp + ph), upper(specInfo.padR, pw - wid)
            end
        end
        return specInfo
    end

    -- The pet group beside a preview, or nil without Show Pets on that tab or on Free Move: button size,
    -- count and growth, the group's size, and its top-left offset from the top-left of the boxW x boxH
    -- box it attaches to (the party frames, or the first or last preview group), by the FB.Anchor rules.
    -- Beside Owner (Party tab) returns its own spec instead (spec.owner, see PF.OwnerPreviewSpec).
    -- w, h, sp: the preview's frame size and spacing; ptSpec: the preview's party target frames
    -- (ns.PT_PreviewSpec), whose room the pets clear as the real ones do.
    function mod.PF_PreviewSpec(party, s, wid, hgt, sp, boxW, boxH, ptSpec)
        local raw = PopFrame.Raw()
        if not raw or raw[party and "party" or "raid"] ~= true then
            return
        end
        local set = PopFrame.View(party and "party" or "raid")
        if set.position == "free" then
            return
        end
        if set.position == "owner" then
            if party then
                return PopFrame.OwnerPreviewSpec(s, wid, hgt, sp)
            end
            return
        end
        local before = set.position == "left"
        local gap, grow, sideName
        if party then
            gap = s.groupSpacing or -1
            if mod.RF_PartyKit() then
                local extra
                before, extra = mod.RF_KitAttach(s, before)
                gap = gap + extra
            end
            gap = gap + mod.PT_PreviewReserve(ptSpec, s.partyHorizontal, before)
            grow = mod._PartyGrowth(s)
            if mod.RF_PartyKit() then
                wid, hgt, sp =
                    PixelSnap(s.frameWidth or 125),
                    PixelSnap(s.frameHeight or 60),
                    PixelSnap(s.cellSpacing or -1)
            else
                -- The party frames' pitch, party target frames along the stack included (PF.Layout's).
                sp = sp + mod.PT_AlongPitch(s, s.partyShowTargets == true)
            end
            if s.partyHorizontal then
                sideName = before and "UP" or "DOWN"
            else
                sideName = before and "LEFT" or "RIGHT"
            end
        else
            gap = mod.RF_GroupSpacing(s)
            grow = s.unitGrowth or "DOWN"
            sideName = s.groupGrowth or "RIGHT"
            -- The grid flow ends in the rightmost column too, so the pets hang off
            -- the same edge a plain RIGHT run uses -- FB.Anchor agrees. Read raw,
            -- PF.OPPOSITE would return nil for it and the side would fall through
            -- to the vertical branch, drawing the pets above the groups.
            if sideName == "DOWNRIGHT" then
                sideName = "RIGHT"
            end
            if before then
                sideName = PopFrame.OPPOSITE[sideName]
            end
        end

        local specInfo = { n = party and 3 or 5, sp = sp, grow = grow, before = before }
        specInfo.w = PixelSnap(math.max(10, wid + (set.extraWidth or 0)))
        specInfo.h = PixelSnap(math.max(10, hgt + (set.extraHeight or 0)))
        if grow == "RIGHT" or grow == "LEFT" then
            specInfo.bw, specInfo.bh = specInfo.n * specInfo.w + (specInfo.n - 1) * sp, specInfo.h
        else
            specInfo.bw, specInfo.bh = specInfo.w, specInfo.n * specInfo.h + (specInfo.n - 1) * sp
        end
        specInfo.ox, specInfo.oy = 0, 0
        -- Party stacks that grow up or left start at the box's bottom or right edge.
        if party and grow == "UP" then
            specInfo.oy = specInfo.bh - boxH
        end
        if party and grow == "LEFT" then
            specInfo.ox = boxW - specInfo.bw
        end
        if sideName == "RIGHT" then
            specInfo.ox = boxW + gap
        elseif sideName == "LEFT" then
            specInfo.ox = -gap - specInfo.bw
        elseif sideName == "DOWN" then
            specInfo.oy = -(boxH + gap)
        else
            specInfo.oy = gap + specInfo.bh
        end
        return specInfo
    end

    -- Shows the spec's pets with the group's top-left at x, y from rel's top-left. s: the settings they
    -- are styled from.
    function mod.PF_ShowPreview(specInfo, s, hostFrame, rel, posX, posY)
        local c = PopFrame.PvColors(s)
        for idx = 1, specInfo.n do
            local f = PopFrame.PvFrame(idx, hostFrame, s, specInfo.w, specInfo.h, c, true)
            local offset = idx - 1
            local fx, fy = posX, posY
            if specInfo.grow == "RIGHT" then
                fx = posX + offset * (specInfo.w + specInfo.sp)
            elseif specInfo.grow == "LEFT" then
                fx = posX + specInfo.bw - specInfo.w - offset * (specInfo.w + specInfo.sp)
            elseif specInfo.grow == "UP" then
                fy = posY - specInfo.bh + specInfo.h + offset * (specInfo.h + specInfo.sp)
            else
                fy = posY - offset * (specInfo.h + specInfo.sp)
            end
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", rel, "TOPLEFT", fx, fy)
        end
        for idx = specInfo.n + 1, #PopFrame.pv do
            PopFrame.pv[idx]:Hide()
        end
        mod.RF_PreviewPetCompact(PopFrame.pv, s, mod._partyPvActive == true, specInfo.grow)
    end

    -- Beside Owner preview: a pet beside each shown party preview frame, and with Hide Self one after
    -- lastF (the last frame along the growth). s: the settings they are styled from.
    function mod.PF_ShowOwnerPreview(specInfo, s, hostFrame, lastF)
        mod.RF_PreviewPetCompact(nil)
        local c = PopFrame.PvColors(s)
        local num = 0
        for idx = 1, 5 do
            local o = mod._partyPvFrames[idx]
            if o and o:IsShown() then
                num = num + 1
                local f = PopFrame.PvFrame(num, hostFrame, s, specInfo.w, specInfo.h, c)
                f:ClearAllPoints()
                PopFrame.OwnerPoint(f, o, specInfo.side, specInfo.gap)
            end
        end
        if specInfo.selfSlot and lastF and num < #PopFrame.PV_PETS then
            num = num + 1
            local f = PopFrame.PvFrame(num, hostFrame, s, specInfo.w, specInfo.h, c)
            f:ClearAllPoints()
            f:SetPoint(specInfo.sPt, lastF, specInfo.sRp, specInfo.sX, specInfo.sY)
        end
        for idx = num + 1, #PopFrame.pv do
            PopFrame.pv[idx]:Hide()
        end
    end

    function mod.PF_HidePreview()
        mod.RF_PreviewPetCompact(nil)
        for _, f in ipairs(PopFrame.pv) do
            f:Hide()
        end
    end

    -- Real-frame previews hide the real frames by alpha; while they do, our own mouse blockers keep the
    -- invisible pet buttons from taking clicks: one over the pet header, and one on each Beside Owner
    -- pet (they sit outside the party frames' blocker). Our frames, so Hide() is combat-legal.
    PopFrame.SetPreviewBlock = function(enabled)
        PopFrame.pvBlockOn = enabled or nil
        local heading = PopFrame.container
        if enabled and PopFrame.active and heading then
            local blk = PopFrame.hdrBlock
            if not blk then
                -- Under the header's parent, so it hides with the header's pet-battle and solo hide.
                blk = CreateFrame("Frame", nil, PopFrame.hider)
                blk:EnableMouse(true)
                PopFrame.hdrBlock = blk
            end
            blk:SetAllPoints(heading)
            blk:SetFrameStrata(heading:GetFrameStrata())
            blk:SetFrameLevel(heading:GetFrameLevel() + 50)
            blk:Show()
        elseif PopFrame.hdrBlock then
            PopFrame.hdrBlock:Hide()
        end
        for _, b in ipairs(PopFrame.ownerButtons) do
            local blk = PopFrame.pvBlock[b]
            if enabled and PopFrame.ownerActive then
                if not blk then
                    blk = CreateFrame("Frame", nil, b)
                    blk:SetAllPoints(b)
                    blk:EnableMouse(true)
                    PopFrame.pvBlock[b] = blk
                end
                blk:SetFrameLevel(b:GetFrameLevel() + 50)
                blk:Show()
            elseif blk then
                blk:Hide()
            end
        end
    end
    mod._PF_SetPreviewBlock = PopFrame.SetPreviewBlock

    -- A frame strata change while blocked: re-seat the blockers.
    function mod._PF_RefreshPreviewBlock()
        if PopFrame.pvBlockOn then
            PopFrame.SetPreviewBlock(true)
        end
    end

    -- The header's placement. FB.Anchor remembers the group it followed in PF.chainTgt (none on Free
    -- Move), which the Friendly Boss / Extra Frames probe compares against. A combat call is deferred
    -- to the combat-end flush by FB.Anchor.
    PopFrame.Anchor = function()
        PopFrame.attachParty = PopFrame.PartyMode()
        if not InCombatLockdown() then
            PopFrame.chainTgt = false
        end
        FB.Anchor(PopFrame)
    end

    function mod.PF_ReAnchor()
        if not InCombatLockdown() then
            PopFrame.anchorDirty = nil
        end
        PopFrame.PlaceSelfPet()
        if PopFrame.active then
            PopFrame.Anchor()
        end
    end

    -- Friendly Boss and Extra Frames can appear, move or go away without a roster change. A group that
    -- moves carries the pets chained after it along, so the header re-anchors only when the group it
    -- follows changes.
    PopFrame.ProbeChain = function()
        if not PopFrame.active then
            return
        end
        local set = PopFrame.Settings()
        if not set or set.position == "free" then
            return
        end
        if (PopFrame.ChainAnchor(set) or false) ~= PopFrame.chainTgt then
            PopFrame.Anchor()
        end
    end

    -- The party layout pass (size, growth, spacing, orientation, the party frames' show/hide edge, the
    -- kit's clearance): re-lays the pets and the party target frames that sit beside the party frames,
    -- delta-gated. The target frames go after the Beside Owner pets they follow and before any
    -- anchoring, so the attached groups are pinned once, on the new reserve.
    function mod.PF_PartyRelayout()
        if not InCombatLockdown() then
            if PopFrame.active and PopFrame.PartyMode() then
                PopFrame.Layout()
            end
            if PopFrame.ownerActive then
                PopFrame.OwnerLayout()
                PopFrame.SetOwnerWatch()
            end
        end
        mod._PT_Layout()
        mod.PF_ReAnchor()
    end

    -- A party settings reload, which owns the pets styled from the party settings (the Beside Owner pets,
    -- and the header beside the party frames): they check their style (restyled only when it changed)
    -- and repaint. Deferred through combat to the combat-end flush.
    function mod.PF_PartyRestyle()
        local headerFrame = PopFrame.active and PopFrame.PartyMode()
        if not (headerFrame or PopFrame.ownerActive) then
            PopFrame.partyRestyleDirty = nil
            return
        end
        if InCombatLockdown() then
            PopFrame.partyRestyleDirty = true
            return
        end
        PopFrame.partyRestyleDirty = nil
        if PopFrame.ownerActive then
            PopFrame.OwnerLayout(true)
            PopFrame.RepaintShown(PopFrame.ownerButtons)
        end
        if headerFrame then
            PopFrame.Layout(true)
        end
        PopFrame.SyncListeners()
    end

    -- Master apply: the options, the raid frames' reloads and the roster flush (below). OOC only;
    -- deferred through combat like the other groups. restyle: a raid settings or profile reload, which
    -- restyles only the pets styled from the raid settings (the party reload that follows it restyles
    -- the others, see ns.PF_PartyRestyle).
    function mod.PF_Apply(restyle)
        if not saved or not saved.profile then
            return
        end
        local raw = PopFrame.Raw()
        if not raw then
            return
        end
        if InCombatLockdown() then
            PopFrame.applyDirty = true
            PopFrame.restyleDirty = PopFrame.restyleDirty or restyle
            return
        end
        -- This pass covers a roster change or a combat-deferred apply still waiting for the flush.
        restyle = restyle or PopFrame.restyleDirty
        PopFrame.dirty, PopFrame.applyDirty, PopFrame.restyleDirty = nil, nil, nil

        -- Beside Owner. Chosen before the party frames exist (early login), neither kind comes up: the
        -- next apply brings the pets up. Only their activation edge checks their style here, before
        -- they show (and paint as they do).
        local chosen = PopFrame.OwnerChosen()
        local ownerFrame = chosen and mod._partySelfButton ~= nil
        if ownerFrame then
            local edge = not PopFrame.ownerActive
            if edge then
                PopFrame.EnsureOwnerBuilt()
                PopFrame.ownerActive = true
                PopFrame.SetOwnerLinks(true)
            end
            PopFrame.OwnerLayout(edge)
            PopFrame.SetOwnerWatch()
            PopFrame.SetTracking(true)
            if edge then
                PopFrame.NotifyReserve()
            end
        elseif PopFrame.ownerActive then
            PopFrame.ownerActive = nil
            PopFrame.SetOwnerLinks(false)
            PopFrame.SetOwnerWatch()
            PopFrame.NotifyReserve()
        end

        if chosen or not PopFrame.Wanted() or not PopFrame.EnsureBuilt() then
            PopFrame.active = nil
            mod.RF_SyncPetCompact()
            PopFrame.chainTgt = nil
            if PopFrame.built then
                PopFrame.container:Hide()
            end
            PopFrame.ClearHider()
            if not ownerFrame then
                PopFrame.SetTracking(false)
            end
            if PopFrame.pvBlockOn then
                PopFrame.SetPreviewBlock(true)
            end
            PopFrame.SyncListeners()
            return
        end

        -- The activation edge checks the style too: settings can change while the header is down.
        local edge = not PopFrame.active
        PopFrame.active = true
        PopFrame.SetTracking(true)
        -- Layout also registers the parent's hide (PF.SetHider) and repaints the pets on screen on a
        -- restyle; the header shows last, laid out, its pets painting as they show. The roster's own
        -- re-assignments paint in the buttons' unit hook.
        PopFrame.Layout((restyle and PopFrame.Ctx() == "raid") or edge)
        mod.PF_ReAnchor()
        if not PopFrame.container:IsShown() then
            PopFrame.container:Show()
        end
        if PopFrame.pvBlockOn then
            PopFrame.SetPreviewBlock(true)
        end
        PopFrame.SyncListeners()
    end

    -- Roster and zoning edges, folded into the raid frames' own passes: the roster change and the zone-in
    -- mark the pets dirty (in combat too), and the raid frames' roster pass, zone-in settle and combat
    -- end each flush once, after their own layout. Both toggles off, nothing is marked.
    function mod.PF_MarkDirty()
        local raw = PopFrame.Raw()
        if raw and (raw.party == true or raw.raid == true) then
            PopFrame.dirty = true
        end
    end

    -- Runs what is waiting: a marked or combat-deferred apply, a combat-deferred party restyle, then a
    -- combat-deferred placement. OOC only; in combat everything stays marked for the combat-end flush.
    function mod.PF_Flush()
        if InCombatLockdown() then
            return
        end
        if PopFrame.dirty or PopFrame.applyDirty then
            mod.PF_Apply()
        end
        if PopFrame.partyRestyleDirty then
            mod.PF_PartyRestyle()
        end
        -- A combat-deferred party target include edge or attribute seed (secure writes), then a
        -- combat-deferred party target layout (a kit clearance edge in combat), before the anchor.
        if mod._ptSelfDirty then
            mod._PT_SyncSelf()
        end
        if mod._ptLayoutDirty then
            mod._PT_Layout()
        end
        if PopFrame.anchorDirty then
            mod.PF_ReAnchor()
        end
    end

    hooksecurefunc(mod, "FB_Apply", PopFrame.ProbeChain)
    hooksecurefunc(mod, "XF_Apply", PopFrame.ProbeChain)

    -- Target, pet and vehicle listeners; each is registered only while pets that need it are on screen
    -- (PF.SyncShownEvents).
    do
        local ev = mod.TakeShell()
        ev:SetScript("OnEvent", function(_, evt, unitToken)
            if not saved then
                return
            end
            if evt == "PLAYER_TARGET_CHANGED" then
                PopFrame.EachShown(PopFrame.TargetFlip)
            else -- UNIT_PET / UNIT_ENTERED_VEHICLE / UNIT_EXITED_VEHICLE
                PopFrame.OnPetChanged(unitToken)
            end
        end)
        PopFrame.eventFrame = ev
    end
end -- PF scope block

Inner.broken = false
