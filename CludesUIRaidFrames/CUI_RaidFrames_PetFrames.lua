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
    local PetKit = {
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
    mod._PF = PetKit

    PetKit.MAX = 40
    PetKit.UNITS = { "pet" }
    for index = 1, 4 do
        PetKit.UNITS[#PetKit.UNITS + 1] = "partypet" .. index
    end
    for index = 1, 40 do
        PetKit.UNITS[#PetKit.UNITS + 1] = "raidpet" .. index
    end
    -- Tracker frames (two tokens each): every token, or while raid pets are off the first seven, which
    -- hold your pet, the party pets and raidpet1-9 (inside a raid the party frames run below ten
    -- members).
    PetKit.ALL_TRACKERS = math.ceil(#PetKit.UNITS / 2)
    PetKit.SMALL_TRACKERS = 7
    PetKit.EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE" }
    -- A party frame's token -> its pet's token.
    PetKit.PET_OF = { player = "pet" }
    for index = 1, 4 do
        PetKit.PET_OF["party" .. index] = "partypet" .. index
    end
    for index = 1, 40 do
        PetKit.PET_OF["raid" .. index] = "raidpet" .. index
    end
    PetKit.DEFAULT_BG = { r = 17 / 255, g = 17 / 255, b = 17 / 255 }
    -- Beside Owner pet -> the party frame it sits beside (your own pet has none); header button -> the
    -- style generation it was last styled at; Beside Owner pet -> its preview mouse blocker.
    PetKit.ownerOf = setmetatable({}, { __mode = "k" })
    PetKit.styledGen = setmetatable({}, { __mode = "k" })
    PetKit.pvBlock = setmetatable({}, { __mode = "k" })

    PetKit.Raw = function()
        return saved and saved.profile and saved.profile.petFrames
    end
    -- The painter's Pet Health Color read (one setting for both tabs, off the per-tab view).
    PetKit.ColorSettings = PetKit.Raw

    -- The Party and Raid tabs each keep their own Position, Extra Width/Height, Free Move spot and Free
    -- Move Growth Direction. A tab reads the shared key until it sets its own: a view over the saved
    -- table that never writes on read. Every other key (the tab toggles, Pet Health Color, Pet Side) is
    -- the saved one.
    PetKit.TAB_KEY = {
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
    PetKit.views = {}
    PetKit.View = function(context)
        local v = PetKit.views[context]
        if v then
            return v
        end
        local keyList = PetKit.TAB_KEY[context]
        v = setmetatable({}, {
            __index = function(_, key)
                local rawValue = PetKit.Raw()
                if not rawValue then
                    return nil
                end
                local tk = keyList[key]
                if tk then
                    local val = rawValue[tk]
                    if val ~= nil then
                        return val
                    end
                end
                return rawValue[key]
            end,
            __newindex = function(_, key, val)
                local rawValue = PetKit.Raw()
                if rawValue then
                    rawValue[keyList[key] or key] = val
                end
            end,
        })
        PetKit.views[context] = v
        return v
    end
    mod.PF_View = PetKit.View

    -- The toggle that counts is the one for the frames on screen: the party frames also run inside
    -- small raids and arenas.
    PetKit.PartyMode = function()
        return not IsInRaid() or mod._PartyInRaid()
    end

    PetKit.Ctx = function()
        return PetKit.PartyMode() and "party" or "raid"
    end

    -- The live tab's view.
    PetKit.Settings = function()
        return PetKit.Raw() and PetKit.View(PetKit.Ctx())
    end

    -- Beside Owner: Show Pets on the Party tab with its Position on Beside Owner, while the party frames
    -- are the ones on screen.
    PetKit.OwnerChosen = function()
        local rawValue = PetKit.Raw()
        return (rawValue and rawValue.party == true and PetKit.PartyMode() and PetKit.View("party").position == "owner")
            or false
    end

    -- The pet header (Beside Owner leaves it down).
    PetKit.Wanted = function()
        local rawValue = PetKit.Raw()
        if not rawValue then
            return false
        end
        if PetKit.PartyMode() then
            return rawValue.party == true and PetKit.View("party").position ~= "owner"
        end
        return rawValue.raid == true
    end

    -- Settings the pets are styled from: the party settings beside the party frames, else the raid's.
    -- The header's follows the mode PF.Layout last laid it out for (PF.styleCtx), so the paint path
    -- never re-derives the mode.
    PetKit.PartySource = function()
        return mod._scaledPartyProxy
    end
    PetKit.StyleSource = function()
        if PetKit.styleCtx == "party" then
            return mod._scaledPartyProxy
        end
        return mod._scaledProfile or saved.profile
    end

    -- Beside Owner pets ignore their party frame's alpha (its range, offline and Buff Manager fades
    -- are the owner's), so the party container's own dims (the options previews) apply here instead.
    PetKit.ContainerAlpha = function()
        local alpha = mod._partyContainerFrame:GetAlpha()
        if issecretvalue(alpha) then
            return 1
        end
        return alpha
    end

    -- As the raid buttons: UnitInRange's first return straight into SetAlphaFromBoolean, which takes
    -- a secret. Its unchecked case is your own units, so your pet stays at full alpha like you do.
    PetKit.ApplyRange = function(petBtn)
        local unitToken = FB.UnitOf(petBtn)
        if not unitToken then
            return
        end
        local ca = PetKit.ownerOf[petBtn] and PetKit.ContainerAlpha() or 1
        local own = UnitIsUnit(unitToken, "pet")
        if issecretvalue(own) then
            own = false
        end
        if not UnitExists(unitToken) or own then
            petBtn:SetAlpha(ca)
            return
        end
        local src = FB.Source(petBtn)
        petBtn:SetAlphaFromBoolean(UnitInRange(unitToken), ca, (src.oorAlpha or 0.4) * ca)
    end

    -- fn(b, unit) on every pet button on screen: the header's, and beside the party frames the Beside
    -- Owner pets and your own pet button.
    PetKit.EachShown = function(func)
        if PetKit.active then
            for unit, petBtn in pairs(PetKit.byUnit) do
                if petBtn:IsVisible() then
                    func(petBtn, unit)
                end
            end
        end
        if PetKit.ownerActive then
            for unit, petBtn in pairs(PetKit.ownerByUnit) do
                if petBtn:IsVisible() then
                    func(petBtn, unit)
                end
            end
            local petSettings = PetKit.selfPet
            if petSettings:IsVisible() then
                func(petSettings, "pet")
            end
        end
    end

    -- Whether a target change can repaint anything: Target Border on in the settings the pets that are
    -- up are styled from. Re-read by every apply and party restyle (PF.SyncListeners).
    PetKit.TargetWanted = function()
        local src = PetKit.active and PetKit.StyleSource()
        if src and src.targetBorderEnabled ~= false then
            return true
        end
        src = PetKit.ownerActive and PetKit.PartySource()
        return (src and src.targetBorderEnabled ~= false) and true or false
    end

    -- Every pet listener runs only while a pet button is on screen (the header hidden solo or in a pet
    -- battle, or the party frames down, leaves none): the trackers' health, name and range, the vehicle
    -- edges, UNIT_PET beside the party frames, and target changes while a Target Border can show. A
    -- button coming on screen paints in full, which covers whatever it missed.
    PetKit.SyncShownEvents = function()
        local wanted = (PetKit.tracking and (PetKit.visCount or 0) > 0) and true or false
        local eventFrame = PetKit.eventFrame
        local tgt = wanted and PetKit.tgtWanted
        if PetKit.tgtEv ~= tgt then
            PetKit.tgtEv = tgt
            if tgt then
                eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
            else
                eventFrame:UnregisterEvent("PLAYER_TARGET_CHANGED")
            end
        end
        local pet = (wanted and PetKit.ownerActive) and true or false
        if PetKit.petEv ~= pet then
            PetKit.petEv = pet
            if pet then
                eventFrame:RegisterEvent("UNIT_PET")
            else
                eventFrame:UnregisterEvent("UNIT_PET")
            end
        end
        if PetKit.shownEv == wanted then
            return
        end
        PetKit.shownEv = wanted
        if wanted then
            eventFrame:RegisterEvent("UNIT_ENTERED_VEHICLE")
            eventFrame:RegisterEvent("UNIT_EXITED_VEHICLE")
        else
            eventFrame:UnregisterEvent("UNIT_ENTERED_VEHICLE")
            eventFrame:UnregisterEvent("UNIT_EXITED_VEHICLE")
        end
        for _, tr in ipairs(PetKit.trackers) do
            PetKit.TrackerEvents(tr, wanted)
        end
    end

    -- The listeners after an apply or a party restyle, which can change the pets that are up and the
    -- Target Border setting.
    PetKit.SyncListeners = function()
        PetKit.tgtWanted = PetKit.TargetWanted()
        PetKit.SyncShownEvents()
    end

    -- One tracker's health, name and range listeners. Your own pet takes no range fade, so its token is
    -- left out of range.
    PetKit.TrackerEvents = function(tr, enabled)
        local frame = tr.frame
        if not enabled then
            frame:UnregisterAllEvents()
            return
        end
        for _, eventFrame in ipairs(PetKit.EVENTS) do
            frame:RegisterUnitEvent(eventFrame, tr.u1, tr.u2)
        end
        if tr.u1 == "pet" then
            frame:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", tr.u2)
        else
            frame:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", tr.u1, tr.u2)
        end
    end

    -- Range re-read with no range update behind it (phasing, the Out of Range Alpha slider, roster
    -- passes): the tail of the raid frames' own range seed.
    function mod._PF_RangeSeed()
        if PetKit.shownEv then
            PetKit.EachShown(PetKit.ApplyRange)
        end
    end

    -- A group member's connection changed: re-read its pet's range.
    function mod._PF_OwnerRange(ownerFrame)
        local point = PetKit.shownEv and PetKit.PET_OF[ownerFrame]
        if not point then
            return
        end
        local petBtn = PetKit.active and PetKit.byUnit[point]
        if petBtn and petBtn:IsVisible() then
            PetKit.ApplyRange(petBtn)
        end
        petBtn = PetKit.ownerActive and PetKit.ownerByUnit[point]
        if petBtn and petBtn:IsVisible() then
            PetKit.ApplyRange(petBtn)
        end
    end

    -- A target change repaints only the pets whose target state flipped (the old and new target).
    PetKit.TargetFlip = function(petBtn, unit)
        if FB.ReadTarget(petBtn, unit) then
            FB.ApplyBorderColor(petBtn)
        end
    end

    -- The full paint, which stamps the occupant it painted (unit + GUID, a secret GUID never stored) so
    -- a re-assignment of the same pet can skip it. A pet that does not exist yet still gets its border.
    PetKit.Refresh = function(petBtn)
        if not FB.Update(petBtn, PetKit) then
            FB.ApplyBorderColor(petBtn)
        end
        PetKit.ApplyRange(petBtn)
        local unit = FB.UnitOf(petBtn)
        local g = unit and UnitGUID(unit)
        if issecretvalue(g) then
            g = nil
        end
        local skinData = GetFFD(petBtn)
        skinData.pfPaintUnit, skinData.pfGuid = unit, g
    end

    -- Repaints a shown button only when its occupant differs from the stamped one (a secret or missing
    -- GUID always repaints).
    PetKit.Revalidate = function(petBtn)
        if not (petBtn and petBtn:IsVisible()) then
            return
        end
        local unit = FB.UnitOf(petBtn)
        local skinData = GetFFD(petBtn)
        if unit and unit == skinData.pfPaintUnit then
            local g = UnitGUID(unit)
            if issecretvalue(g) then
                g = nil
            end
            if g and g == skinData.pfGuid then
                return
            end
        end
        PetKit.Refresh(petBtn)
    end

    -- Every pet button on screen (cross-module colour and name pushes).
    function mod._PF_RefreshVisible()
        PetKit.EachShown(PetKit.Refresh)
    end

    -- The buttons of one list that are on screen (PF.buttons or PF.ownerButtons), after a settings
    -- reload or a party/raid flip.
    PetKit.RepaintShown = function(entries)
        for _, petBtn in ipairs(entries) do
            if petBtn:IsVisible() then
                PetKit.Refresh(petBtn)
            end
        end
    end

    -- The pet behind one owner's token may have changed while its button kept the same unit attribute:
    -- a new pet (UNIT_PET, Beside Owner only: the pet header re-assigns its own buttons on it), or the
    -- owner entering or leaving a vehicle, which the pet token then stands for. Only that owner's pet
    -- buttons are re-checked. owner: the event's unit.
    PetKit.OnPetChanged = function(ownerFrame)
        local point = ownerFrame and PetKit.PET_OF[ownerFrame]
        if not point then
            return
        end
        if PetKit.active then
            PetKit.Revalidate(PetKit.byUnit[point])
        end
        if PetKit.ownerActive then
            PetKit.Revalidate(PetKit.ownerByUnit[point])
            if point == "pet" then
                PetKit.Revalidate(PetKit.selfPet)
            end
        end
    end

    -- The party container's alpha changed (the options previews): re-apply the Beside Owner pets'.
    function mod._PF_AlphaSync()
        if not PetKit.ownerActive then
            return
        end
        for _, petBtn in ipairs(PetKit.ownerButtons) do
            if PetKit.ownerOf[petBtn] and petBtn:IsVisible() then
                PetKit.ApplyRange(petBtn)
            end
        end
    end

    -- The side a group attached beside the party frames takes, the Party Frames kit's flip included.
    PetKit.KitSide = function(place)
        local prior = place == "left"
        if mod.RF_PartyKit() then
            prior = mod.RF_KitAttach(saved.profile, prior)
        end
        return prior
    end

    -- The pet group goes after Friendly Boss and Extra Frames when they sit on the same side. Beside
    -- the party frames only a Show in Dungeons boss group is attached there to follow, and Extra
    -- Frames (raid only) never is.
    PetKit.ChainAnchor = function(pset)
        if pset.position == "free" or pset.position == "owner" then
            return
        end
        local party = PetKit.PartyMode()
        local fontStr = FB.Settings()
        if fontStr and FB.built and FB.container:IsShown() then
            if party then
                if
                    fontStr.position ~= "free"
                    and fontStr.showInDungeons == true
                    and PetKit.KitSide(fontStr.position) == PetKit.KitSide(pset.position)
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
        local extraFrames = mod._XF
        local xs = extraFrames.Settings()
        if xs and xs.position == pset.position and extraFrames.built and extraFrames.container and extraFrames.container:IsShown() then
            return extraFrames.container
        end
    end

    -- map: the unit -> button map the button keeps itself in (none for your own Beside Owner pet).
    PetKit.StyleButton = function(petBtn, map)
        petBtn:RegisterForClicks("AnyUp")
        petBtn:SetAttribute("*type1", "target")
        -- The engine gates SecureUnitButton's togglemenu; route right-click through a SecureActionButton proxy so the menu works without taint.
        CludesUI.AttachSecureUnitMenu(petBtn)
        FB.BuildVisuals(petBtn, true)

        petBtn:HookScript("OnShow", function(self)
            PetKit.visCount = (PetKit.visCount or 0) + 1
            -- A button showing again holds its unit's map entry, which another button may have taken
            -- and dropped while this one was off screen with the same unit.
            if map then
                local unit = self:GetAttribute("unit")
                local skinData = GetFFD(self)
                local old = skinData.pfUnit
                if old and old ~= unit and map[old] == self then
                    map[old] = nil
                end
                if unit then
                    map[unit] = self
                end
                skinData.pfUnit = unit
            end
            -- Header buttons hidden at the last restyle catch up as they show.
            local g = PetKit.styledGen[self]
            if g and g ~= PetKit.styleGen then
                PetKit.StyleHeaderButton(self)
            end
            PetKit.Refresh(self)
            PetKit.SyncShownEvents()
        end)
        petBtn:HookScript("OnHide", function(self)
            PetKit.visCount = math.max(0, (PetKit.visCount or 0) - 1)
            local skinData = GetFFD(self)
            skinData.pfPaintUnit, skinData.pfGuid = nil, nil
            PetKit.SyncShownEvents()
        end)
        petBtn:HookScript("OnEnter", function(self)
            FB.hov[self] = true
            FB.ApplyBorderColor(self)
        end)
        petBtn:HookScript("OnLeave", function(self)
            FB.hov[self] = nil
            FB.ApplyBorderColor(self)
        end)
        -- The header (or, beside the party frames, the party frame's unit snippet) re-units buttons as
        -- pets come and go, in combat too. Both re-set every button's unit on each re-process (roster,
        -- name and pet events), so most fires re-confirm the pet already painted: those keep only the
        -- map write. A hidden button paints as it shows.
        petBtn:HookScript("OnAttributeChanged", function(self, name, value)
            if name ~= "unit" then
                return
            end
            local skinData = GetFFD(self)
            if map then
                local old = skinData.pfUnit
                if old and map[old] == self then
                    map[old] = nil
                end
                if value then
                    map[value] = self
                end
                skinData.pfUnit = value
            end
            if not value or not self:IsVisible() then
                skinData.pfPaintUnit, skinData.pfGuid = nil, nil
                if not value then
                    FB.tgt[self] = nil
                end
                return
            end
            if value == skinData.pfPaintUnit then
                local g = UnitGUID(value)
                if issecretvalue(g) then
                    g = nil
                end
                if g and g == skinData.pfGuid then
                    return
                end
            end
            PetKit.Refresh(self)
        end)

        -- Full click-cast / hovercast binding suite (mouseover heals included)
        if mod.CC_RegisterFrame then
            mod.CC_RegisterFrame(petBtn)
        end
    end

    -- One header button at the header's current size and style.
    PetKit.StyleHeaderButton = function(petBtn)
        if not PetKit.w then
            return
        end
        local src = PetKit.StyleSource()
        FB.StyleVisuals(petBtn, src, PetKit.w, PetKit.h, ResolveHealthTexture(src), src.customBgColor or PetKit.DEFAULT_BG)
        PetKit.styledGen[petBtn] = PetKit.styleGen
    end

    -- Every setting the button styler reads (FB.StyleVisuals with FB.StyleBorder; the size is checked on
    -- its own), plus the UI scale its pixel-sized borders follow, gathered into a reused list, so a
    -- reload that changed none of them leaves the pets' fonts, textures and borders alone. The hover and
    -- target borders are painted, not styled.
    PetKit.STYLE_N = 26 + mod.RF_TEXT_STYLE_N
    PetKit.fp = {}
    PetKit.fpNew = {}
    PetKit.StyleInputs = function(inputs, src, texPath)
        local bgRGB = src.customBgColor or PetKit.DEFAULT_BG
        local borderRGB = src.borderColor
        inputs[1], inputs[2], inputs[3], inputs[4], inputs[5] = bgRGB.r, bgRGB.g, bgRGB.b, src.bgDarkness, texPath
        inputs[6], inputs[7] = src.healthVerticalFill, src.healthBarOpacity
        inputs[8], inputs[9] = CludesUI.GetFontPath("raidFrames"), CludesUI.GetFontOutlineFlag("raidFrames")
        inputs[10], inputs[11], inputs[12], inputs[13], inputs[14] = src.borderSize, borderRGB and borderRGB.r, borderRGB and borderRGB.g, borderRGB and borderRGB.b, src.borderAlpha
        inputs[15], inputs[16], inputs[17] = src.borderTexture, src.borderSizePx, src.borderBehind
        inputs[18], inputs[19] = src.borderTextureOffset, src.borderTextureOffsetY
        inputs[20], inputs[21] = src.borderTextureShiftX, src.borderTextureShiftY
        inputs[22] = UIParent:GetEffectiveScale()
        inputs[23] = src.healthInvertFill
        inputs[24], inputs[25] = src.cornerRadius, src.cornerMask
        -- The texts: the plan signature, then offsets and size of each (t[26] on).
        mod.RF_TextStyleInputs(inputs, 25, src)
        inputs[PetKit.STYLE_N] = src.textureBg -- Textured Background
    end

    -- True when the inputs differ from the ones last styled under key ("hdr": the header, "owner": the
    -- Beside Owner pets, "pt": the party target frames), which they then become (two lists trade
    -- places, nothing allocated). extra(t), when given, writes the key's own inputs after the shared
    -- ones, n slots in all (the party target frames' colour settings). The second return is the first
    -- slot that differs (0 with nothing styled yet), so a key with extra slots can tell a change to
    -- its own inputs alone (past PF.STYLE_N) from one the styler reads.
    PetKit.StyleChanged = function(key, src, texPath, extra, num)
        local new = PetKit.fpNew
        PetKit.StyleInputs(new, src, texPath)
        if extra then
            extra(new)
        end
        local old, at = PetKit.fp[key], 0
        if old then
            for index = 1, num or PetKit.STYLE_N do
                if old[index] ~= new[index] then
                    at = index
                    break
                end
            end
            if at == 0 then
                return false
            end
        end
        PetKit.fp[key] = new
        PetKit.fpNew = old or {}
        return true, at
    end

    PetKit.CompactStyleInput = function(inputs)
        inputs[PetKit.STYLE_N + 1] = mod.RF_CompactOn(PetKit.StyleSource(), PetKit.styleCtx == "party")
    end

    -- Header buttons: five in one column beside the party frames, all forty (eight columns) once raid
    -- pets are on. The column count caps what the header shows, so it never makes a button itself.
    PetKit.Capacity = function()
        local rawValue = PetKit.Raw()
        return (rawValue and rawValue.raid == true) and PetKit.MAX or 5
    end

    -- A header makes children only while visible, so the buttons up to the capacity are made up front
    -- (the raid headers' startingIndex pass, its parent shown for it) and set up once; the header then
    -- assigns pets to them. The pass leaves the header hidden for the apply to show laid out. With the
    -- UI hidden (a cinematic, Alt-Z) nothing is made and the next apply tries again. OOC only.
    PetKit.EnsureBuilt = function()
        local cap = PetKit.Capacity()
        local have = #PetKit.buttons
        if have >= cap then
            return true
        end
        local heading = PetKit.container
        if not heading then
            -- The header's parent carries its pet-battle and solo hide (see PF.SetHider).
            local hideHost = CreateFrame("Frame", nil, UIParent)
            hideHost:SetAllPoints(UIParent)
            PetKit.hider = hideHost
            heading = CreateFrame("Frame", "ERFPetHeader", hideHost, "SecureGroupPetHeaderTemplate")
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
            PetKit.container = heading
            -- Switched on with a preview up: dim it like the other real frames.
            if mod._raidPvActive or mod._partyPvActive then
                mod._SetRealFramesPreviewHidden(true)
            end
        end
        if not heading[cap] then
            local hideHost = PetKit.hider
            local hid = not hideHost:IsShown()
            heading:Hide()
            if hid then
                hideHost:Show()
            end
            heading:SetAttribute("maxColumns", cap > 5 and 8 or 1)
            heading:SetAttribute("startingIndex", 1 - cap)
            heading:Show()
            heading:SetAttribute("startingIndex", 1)
            heading:Hide()
            if hid then
                hideHost:Hide()
            end
        end
        for index = have + 1, cap do
            local petBtn = heading[index]
            if not petBtn then
                break
            end
            GetFFD(petBtn)._petHeader = true
            PetKit.StyleButton(petBtn, PetKit.byUnit)
            FB.src[petBtn] = PetKit.StyleSource
            PetKit.styledGen[petBtn] = 0
            PetKit.buttons[index] = petBtn
        end
        local num = #PetKit.buttons
        if num == 0 then
            return false
        end
        -- New buttons take their size on the next layout.
        if num > have then
            PetKit.w = nil
        end
        PetKit.EnsureTrackers(num >= PetKit.MAX and PetKit.ALL_TRACKERS or PetKit.SMALL_TRACKERS)
        PetKit.built = true
        return true
    end

    -- Per-event slices of the full paint (PF.Refresh): health events repaint the health value and texts,
    -- name events the name, range updates the range fade.
    PetKit.PaintHealth = function(petBtn, unit)
        if UnitExists(unit) then
            FB.PaintHealth(petBtn, unit, FB.Source(petBtn))
        end
    end
    PetKit.PaintName = function(petBtn, unit)
        if UnitExists(unit) then
            FB.PaintName(petBtn, unit, FB.Source(petBtn))
        end
    end

    -- The event's pet is on the header button holding it, and beside the party frames on its Beside
    -- Owner pet (your pet on your own pet button or on the party frame showing you: one of them shows).
    PetKit.OnTrackerEvent = function(_, evt, unit)
        local paint = PetKit.PaintHealth
        if evt == "UNIT_IN_RANGE_UPDATE" then
            paint = PetKit.ApplyRange
        elseif evt == "UNIT_NAME_UPDATE" then
            paint = PetKit.PaintName
        end
        local petBtn = PetKit.byUnit[unit]
        if petBtn and petBtn:IsVisible() then
            paint(petBtn, unit)
        end
        if PetKit.ownerActive then
            petBtn = PetKit.ownerByUnit[unit]
            if petBtn and petBtn:IsVisible() then
                paint(petBtn, unit)
            end
            petBtn = PetKit.selfPet
            if unit == "pet" and petBtn:IsVisible() then
                paint(petBtn, unit)
            end
        end
    end

    -- Up to n tracker frames, two pet tokens each (RegisterUnitEvent takes two units), from the shell
    -- pool. Frames added while pets are on screen listen at once (the listeners switch on edges).
    PetKit.EnsureTrackers = function(num)
        for k = #PetKit.trackers + 1, num do
            local index = 2 * k - 1
            local inputs = mod.TakeShell()
            inputs:SetScript("OnEvent", PetKit.OnTrackerEvent)
            local tr = { frame = inputs, u1 = PetKit.UNITS[index], u2 = PetKit.UNITS[index + 1] }
            PetKit.trackers[k] = tr
            if PetKit.shownEv then
                PetKit.TrackerEvents(tr, true)
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
    PetKit.OWNER_SNIPPET = [[
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
    PetKit.EnsureOwnerBuilt = function()
        if PetKit.ownerBuilt then
            return
        end
        PetKit.ownerBuilt = true
        -- Your pet hangs off the container, not the self button, so it can outlive Hide Self.
        local petSettings = CreateFrame("Button", nil, mod._partyContainerFrame, "SecureUnitButtonTemplate")
        petSettings:SetAttribute("unit", "pet")
        petSettings:Hide()
        PetKit.StyleButton(petSettings)
        FB.src[petSettings] = PetKit.PartySource
        PetKit.selfPet = petSettings
        PetKit.ownerButtons[1] = petSettings
        for _, ownerFrame in ipairs(mod._partyAllButtons) do
            if ownerFrame ~= mod._partySelfButton then
                local petBtn = CreateFrame("Button", nil, ownerFrame, "SecureUnitButtonTemplate")
                petBtn:Hide()
                petBtn:SetIgnoreParentAlpha(true)
                PetKit.ownerOf[petBtn] = ownerFrame
                PetKit.StyleButton(petBtn, PetKit.ownerByUnit)
                FB.src[petBtn] = PetKit.PartySource
                PetKit.ownerButtons[#PetKit.ownerButtons + 1] = petBtn
                SecureHandlerSetFrameRef(ownerFrame, "pfpet", petBtn)
                SecureHandlerSetFrameRef(ownerFrame, "pfself", petSettings)
            end
        end
        PetKit.EnsureTrackers(PetKit.SMALL_TRACKERS)
    end

    -- The party frames' one unit snippet, installed while the Beside Owner pets or the party target
    -- frames' Include Own Target gate (ns._ptNoSelf) need it, with the pet part switched by pf-on.
    -- Only changed attributes are written. OOC only.
    PetKit.SyncUnitSnippet = function()
        local pets = PetKit.ownerActive and true or nil
        local code = (pets or mod._ptNoSelf) and PetKit.OWNER_SNIPPET or nil
        for _, owner in ipairs(mod._partyAllButtons) do
            if owner ~= mod._partySelfButton then
                if owner:GetAttribute("pf-on") ~= pets then
                    owner:SetAttribute("pf-on", pets)
                end
                if owner:GetAttribute("refreshUnitChange") ~= code then
                    owner:SetAttribute("refreshUnitChange", code)
                end
            end
        end
    end
    mod.PF_SyncUnitSnippet = PetKit.SyncUnitSnippet

    -- Switches the snippet's pet part on or off; on, seeds each pet's unit from its frame's current one
    -- (written as the snippet does, the same token included). OOC only.
    PetKit.SetOwnerLinks = function(enabled)
        if enabled then
            for _, petBtn in ipairs(PetKit.ownerButtons) do
                local owner = PetKit.ownerOf[petBtn]
                if owner then
                    local unit = owner:GetAttribute("unit")
                    petBtn:SetAttribute("unit", unit and PetKit.PET_OF[unit])
                end
            end
        end
        PetKit.SyncUnitSnippet()
    end

    -- Unit watches on the Beside Owner pets run only while the party frames are on screen. OOC only.
    PetKit.SetOwnerWatch = function()
        local wanted = (PetKit.ownerActive and mod._partyContainerFrame:IsShown()) and true or false
        if PetKit.watching ~= wanted then
            PetKit.watching = wanted
            for _, petBtn in ipairs(PetKit.ownerButtons) do
                if PetKit.ownerOf[petBtn] then
                    if wanted then
                        RegisterUnitWatch(petBtn)
                    else
                        UnregisterUnitWatch(petBtn)
                        petBtn:Hide()
                    end
                end
            end
        end
        PetKit.PlaceSelfPet()
    end

    -- Party frame size (the raid frame size under the Party Frames layout, whose size is its portrait
    -- box, as Friendly Boss does).
    PetKit.PartySize = function(src)
        local wid, hgt, petSettings = mod.RF_PartyDims(saved.profile)
        if mod.RF_PartyKit() then
            wid, hgt, petSettings = src.frameWidth or 125, src.frameHeight or 60, src.cellSpacing or -1
        end
        return wid, hgt, petSettings
    end

    -- A tab's pet size (its frames' size plus that tab's Extra Width/Height), spacing and growth: the
    -- party frames' size and stacking on the Party tab, the raid frame size and growth on the Raid tab.
    -- Free Move takes the tab's Growth Direction when one is set, its columns turned across it.
    PetKit.Geometry = function(context)
        local src = mod._scaledProfile or saved.profile
        local wid, hgt, petSettings, unitGrowth, groupGrowth
        if context == "party" then
            wid, hgt, petSettings = PetKit.PartySize(src)
            unitGrowth = mod._PartyGrowth(saved.profile)
            groupGrowth = (unitGrowth == "RIGHT" or unitGrowth == "LEFT") and "DOWN" or "RIGHT"
        else
            wid, hgt, petSettings = src.frameWidth or 125, src.frameHeight or 60, src.cellSpacing or -1
            unitGrowth, groupGrowth =
                mod._RFEffectiveGrowth(src.unitGrowth or "DOWN", src.groupGrowth or "RIGHT", true)
        end
        if mod.RF_CompactOn(context == "party" and mod._partyProxy or src, context == "party") then
            petSettings = mod.RF_OnePixel(context == "party")
        end
        local v = PetKit.View(context)
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
        petSettings = CludesUI.PP.SnapForES(petSettings, (PetKit.container or UIParent):GetEffectiveScale())
        return wid, hgt, petSettings, unitGrowth, groupGrowth
    end

    -- Pet Side, fitted to the party frames' orientation: across the stack only (Left/Right beside
    -- stacked frames, Above/Below horizontal ones), so a pet never lands on the next frame. A choice
    -- that no longer fits reads as the default until it fits again. s: the profile (or preview view).
    PetKit.OwnerSide = function(src)
        local rawValue = PetKit.Raw()
        local edgeSide = rawValue and rawValue.ownerSide
        if src.partyHorizontal then
            if edgeSide ~= "above" and edgeSide ~= "below" then
                edgeSide = "below"
            end
        elseif edgeSide ~= "left" and edgeSide ~= "right" then
            edgeSide = "right"
        end
        return edgeSide
    end
    function mod.PF_OwnerSide()
        return PetKit.OwnerSide(saved.profile)
    end

    -- The side the pets take and the extra gap: the Party Frames kit moves them off its outside auras
    -- as it does the Friendly Boss group.
    PetKit.ResolveOwnerSide = function(src)
        local edgeSide = PetKit.OwnerSide(src)
        local extra = 0
        if mod.RF_PartyKit() then
            local prior = edgeSide == "left" or edgeSide == "above"
            prior, extra = mod.RF_KitAttach(src, prior)
            if src.partyHorizontal then
                edgeSide = prior and "above" or "below"
            else
                edgeSide = prior and "left" or "right"
            end
        end
        return edgeSide, extra
    end

    PetKit.OwnerPoint = function(petBtn, ownerFrame, edgeSide, spacing)
        if edgeSide == "left" then
            petBtn:SetPoint("TOPRIGHT", ownerFrame, "TOPLEFT", -spacing, 0)
        elseif edgeSide == "below" then
            petBtn:SetPoint("TOPLEFT", ownerFrame, "BOTTOMLEFT", 0, -spacing)
        elseif edgeSide == "above" then
            petBtn:SetPoint("BOTTOMLEFT", ownerFrame, "TOPLEFT", 0, spacing)
        else
            petBtn:SetPoint("TOPLEFT", ownerFrame, "TOPRIGHT", spacing, 0)
        end
    end

    -- Size, side and style of the Beside Owner pets: only what changed is touched (the party layout pass
    -- runs this on every roster edge). restyle (a settings reload) checks the style inputs, and restyles
    -- the fonts, textures and borders only when they changed; a size change alone resizes. OOC only.
    PetKit.OwnerLayout = function(needsRestyle)
        local wid, hgt, petSettings = PetKit.Geometry("party")
        local edgeSide, extra = PetKit.ResolveOwnerSide(saved.profile)
        local baseGap = PixelSnap(petSettings)
        local spacing = baseGap + PixelSnap(extra)
        local didResize = wid ~= PetKit.ownerW or hgt ~= PetKit.ownerH
        local moved = edgeSide ~= PetKit.ownerSideCur or spacing ~= PetKit.ownerGap
        PetKit.ownerW, PetKit.ownerH, PetKit.ownerSideCur, PetKit.ownerGap, PetKit.ownerBaseGap = wid, hgt, edgeSide, spacing, baseGap
        local src, texPath
        local didRestyle = false
        if needsRestyle then
            src = PetKit.PartySource()
            texPath = ResolveHealthTexture(src)
            didRestyle = PetKit.StyleChanged("owner", src, texPath)
        end
        if didRestyle then
            local bgRGB = src.customBgColor or PetKit.DEFAULT_BG
            for _, petBtn in ipairs(PetKit.ownerButtons) do
                petBtn:SetSize(wid, hgt)
                FB.StyleVisuals(petBtn, src, wid, hgt, texPath, bgRGB)
            end
        elseif didResize then
            for _, petBtn in ipairs(PetKit.ownerButtons) do
                petBtn:SetSize(wid, hgt)
                FB.SizeVisuals(petBtn, wid, hgt)
            end
        end
        if moved then
            for _, petBtn in ipairs(PetKit.ownerButtons) do
                local owner = PetKit.ownerOf[petBtn]
                if owner then
                    petBtn:ClearAllPoints()
                    PetKit.OwnerPoint(petBtn, owner, edgeSide, spacing)
                end
            end
        end
        if didResize or moved then
            PetKit.PlaceSelfPet(true)
            PetKit.NotifyReserve()
        end
    end

    -- Your own pet: beside the self button while that shows you. With Hide Self (in a group), in your
    -- frame's empty slot after the last party frame: seated here, then re-seated by the party frames'
    -- unit snippet after whichever frame the header fills last, so joins, leaves and re-sorts in combat
    -- carry it along. While the party header shows you, that frame's own pet has it and this one stays
    -- hidden. Repeat calls with nothing changed return at once. OOC only.
    PetKit.PlaceSelfPet = function(force)
        local petBtn = PetKit.selfPet
        if not petBtn then
            return
        end
        if InCombatLockdown() then
            PetKit.anchorDirty = true
            return
        end
        local mode = "off"
        if PetKit.watching then
            local m = mod._partySelfMode
            if m == "button" or (m == "hidden" and IsInGroup()) then
                mode = m
            end
        end
        if mode == "off" then
            if force or PetKit.spMode ~= "off" then
                PetKit.spMode = "off"
                petBtn:SetAttribute("pf-hs", nil)
                UnregisterUnitWatch(petBtn)
                petBtn:Hide()
            end
            return
        end
        local growDir = mod._PartyGrowth(saved.profile)
        local _, _, psp = mod.RF_PartyDims(saved.profile)
        -- The party frames' pitch: spacing, plus the room party target frames along the stack take.
        local slotGap = PixelSnap(psp) + mod.PT_AlongPitch(saved.profile)
        if
            not force
            and mode == PetKit.spMode
            and PetKit.ownerSideCur == PetKit.spSide
            and PetKit.ownerGap == PetKit.spGap
            and growDir == PetKit.spGrow
            and slotGap == PetKit.spSlotGap
        then
            return
        end
        PetKit.spMode, PetKit.spSide, PetKit.spGap, PetKit.spGrow, PetKit.spSlotGap =
            mode, PetKit.ownerSideCur, PetKit.ownerGap, growDir, slotGap
        if mode == "hidden" then
            local point, rp, posX, posY, base
            if growDir == "UP" then
                point, rp, posX, posY, base = "BOTTOMLEFT", "TOPLEFT", 0, slotGap, "BOTTOMLEFT"
            elseif growDir == "RIGHT" then
                point, rp, posX, posY, base = "TOPLEFT", "TOPRIGHT", slotGap, 0, "TOPLEFT"
            elseif growDir == "LEFT" then
                point, rp, posX, posY, base = "TOPRIGHT", "TOPLEFT", -slotGap, 0, "TOPRIGHT"
            else
                point, rp, posX, posY, base = "TOPLEFT", "BOTTOMLEFT", 0, -slotGap, "TOPLEFT"
            end
            petBtn:SetAttribute("pf-pt", point)
            petBtn:SetAttribute("pf-rp", rp)
            petBtn:SetAttribute("pf-x", posX)
            petBtn:SetAttribute("pf-y", posY)
            petBtn:SetAttribute("pf-hs", true)
            local heading = mod._partyHeader
            local last
            for index = 1, 5 do
                local c = heading[index]
                if c and c:IsShown() and c:GetAttribute("unit") then
                    last = c
                end
            end
            petBtn:ClearAllPoints()
            if last then
                petBtn:SetPoint(point, last, rp, posX, posY)
            else
                petBtn:SetPoint(base, heading, base, 0, 0)
            end
        else
            petBtn:SetAttribute("pf-hs", nil)
            petBtn:ClearAllPoints()
            PetKit.OwnerPoint(petBtn, mod._partySelfButton, PetKit.ownerSideCur, PetKit.ownerGap)
        end
        RegisterUnitWatch(petBtn)
    end

    -- A Show in Dungeons boss group beside the party frames clears the Beside Owner pets' column, and
    -- the party target frames follow the pets on their side.
    PetKit.NotifyReserve = function()
        mod._PT_Layout()
        local fontStr = FB.Settings()
        if FB.built and fontStr and fontStr.showInDungeons == true then
            FB.Anchor()
        end
    end

    -- The room the Beside Owner pets take on the side a group attaches to the party frames (horizontal:
    -- the party frames' orientation; before: left, or above horizontal frames).
    function mod.PF_OwnerReserve(horizontal, prior)
        local edgeSide = PetKit.ownerActive and PetKit.ownerSideCur
        if not edgeSide then
            return 0
        end
        if horizontal then
            if (prior and edgeSide == "above") or (not prior and edgeSide == "below") then
                return PetKit.ownerH + PetKit.ownerBaseGap
            end
        elseif (prior and edgeSide == "left") or (not prior and edgeSide == "right") then
            return PetKit.ownerW + PetKit.ownerBaseGap
        end
        return 0
    end

    -- Whether either kind of pet is up. Its listeners follow the pets on screen (PF.SyncShownEvents),
    -- the vehicle edges among them: an owner entering or leaving a vehicle swaps what its pet token
    -- stands for without touching any unit attribute (PF.OnPetChanged re-checks that owner's pet).
    PetKit.SetTracking = function(enabled)
        if PetKit.tracking == enabled then
            return
        end
        PetKit.tracking = enabled
        PetKit.SyncShownEvents()
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
    PetKit.SetHider = function(solo)
        local m = solo and "[petbattle] hide; show"
            or "[petbattle] hide; [@raid1,exists][@party1,exists][group] show; hide"
        if PetKit.hiderMacro ~= m then
            RegisterStateDriver(PetKit.hider, "visibility", m)
            PetKit.hiderMacro = m
        end
    end

    -- Teardown, after the header is hidden: the driver goes and the parent shows again, so a later build
    -- makes its buttons under a shown parent. OOC only.
    PetKit.ClearHider = function()
        if not PetKit.hiderMacro then
            return
        end
        UnregisterStateDriver(PetKit.hider, "visibility")
        PetKit.hiderMacro = nil
        PetKit.hider:Show()
    end

    -- Show Groups as a groupFilter: nil with every group on, one cached string per group set.
    PetKit.gf = {}
    PetKit.RaidGroupFilter = function()
        local vg = mod._VisibleGroups() -- Mythic 5-8 aware (read-only)
        if not vg then
            return nil
        end
        local mask = 0
        for gi = 1, 8 do
            if vg[gi] ~= false then
                mask = mask + 2 ^ (gi - 1)
            end
        end
        if mask == 255 then
            return nil
        end
        local text = PetKit.gf[mask]
        if not text then
            text = ""
            for gi = 1, 8 do
                if vg[gi] ~= false then
                    text = (text == "") and tostring(gi) or (text .. "," .. gi)
                end
            end
            PetKit.gf[mask] = text
        end
        return text
    end

    -- Size and growth follow the frames on screen (the party frames' in party mode, else the raid
    -- frames'), plus that tab's size offsets. Roster edges come through here too, so only what changed
    -- is touched: restyle (a settings or profile reload) and a party/raid flip restyle only when the
    -- style inputs changed, a size change alone resizes, and buttons off screen catch up as they show.
    -- Both also repaint the pets on screen, whose paint reads the settings too. OOC only.
    PetKit.Layout = function(needsRestyle)
        local context = PetKit.Ctx()
        local party = context == "party"
        local wid, hgt, petSettings, unitGrowth, groupGrowth = PetKit.Geometry(context)
        local heading = PetKit.container
        local didResize = wid ~= PetKit.w or hgt ~= PetKit.h
        PetKit.w, PetKit.h, PetKit.sp, PetKit.unitGrowth, PetKit.groupGrowth = wid, hgt, petSettings, unitGrowth, groupGrowth
        local flipped = PetKit.styleCtx ~= context
        local didRestyle = false
        if needsRestyle or flipped then
            PetKit.styleCtx = context
            local ss = PetKit.StyleSource()
            didRestyle =
                PetKit.StyleChanged("hdr", ss, ResolveHealthTexture(ss), PetKit.CompactStyleInput, PetKit.STYLE_N + 1)
        end
        if didResize then
            for _, petBtn in ipairs(PetKit.buttons) do
                petBtn:SetSize(wid, hgt)
            end
        end
        if didRestyle or didResize then
            PetKit.styleGen = (PetKit.styleGen or 0) + 1
            for _, petBtn in ipairs(PetKit.buttons) do
                if petBtn:IsVisible() then
                    if didRestyle then
                        PetKit.StyleHeaderButton(petBtn)
                    else
                        FB.SizeVisuals(petBtn, wid, hgt)
                        PetKit.styledGen[petBtn] = PetKit.styleGen
                    end
                end
            end
        end
        -- Before the header re-runs below: the pets it re-assigns paint in their unit hook, and the
        -- ones it shows as they show.
        if needsRestyle or flipped then
            PetKit.RepaintShown(PetKit.buttons)
        end

        local src = mod._scaledProfile or saved.profile
        -- Party: Small Raid mode shows only group 1 in the party frames, and your pet shows solo while
        -- the party frames do. Raid: the groups Show Groups keeps.
        local group
        if party then
            local g = mod._SmallRaidGroup()
            group = g and tostring(g) or nil
        else
            group = PetKit.RaidGroupFilter()
        end
        -- Beside the party frames the pets keep the party frames' pitch, which party target frames along
        -- the stack open (the kit's pets take the raid frame size, which never lines up with them).
        local pitch = petSettings
        if party and not mod.RF_PartyKit() and PetKit.View("party").position ~= "free" then
            pitch = petSettings + mod.PT_AlongPitch(saved.profile)
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
            party and PixelSnap(src.groupSpacing or 8) or mod.RF_GroupSpacing(src),
            changed
        )
        changed = SetAttr(heading, "columnAnchorPoint", mod._RFColAnchor(unitGrowth, groupGrowth), changed)
        changed = SetAttr(heading, "maxColumns", #PetKit.buttons >= PetKit.MAX and 8 or 1, changed)
        if changed then
            heading:SetAttribute("_ignore", nil)
        end
        -- Blizzard never clears a shown button's anchors, and a leftover column anchor pins button 1 to
        -- the header's old size, so a new size or layout re-lays from cleared anchors (as the merged raid
        -- header does). One write of a spare attribute then re-runs the header once on the final
        -- attributes (clearing _ignore runs nothing, and a new size alone changes no attribute), with
        -- no pet hidden and re-shown. A header not on screen re-runs as it shows.
        if didResize or changed then
            for _, petBtn in ipairs(PetKit.buttons) do
                petBtn:ClearAllPoints()
            end
            heading:SetAttribute("pf-relayout", not heading:GetAttribute("pf-relayout"))
        end
        -- Last, so a parent that shows here runs the header once on the final attributes.
        PetKit.SetHider(solo)
        mod.RF_SyncPetCompact()
    end

    -- Free Move: the header is pinned at the corner its pets grow from, so pet 1 stays put as pets come
    -- and go. The overlay covers five pets; until its first drag they are centred on freePos. ctx: the
    -- tab whose spot and size this is.
    PetKit.FreeCorner = function(keySet, context)
        local wid, hgt, petSettings, unitGrowth, groupGrowth = PetKit.Geometry(context)
        local vertical = unitGrowth ~= "RIGHT" and unitGrowth ~= "LEFT"
        local hDir = vertical and groupGrowth or unitGrowth
        local vDir = vertical and unitGrowth or groupGrowth
        if vertical then
            hgt = 5 * hgt + 4 * petSettings
        else
            wid = 5 * wid + 4 * petSettings
        end
        local region = keySet.freeRect
        local corner, posX, posY = FB.CornerPin(hDir, vDir, region)
        if not region then
            local p = keySet.freePos
            local cx, cy = p and p.x or 100, p and p.y or 0
            posX = (hDir == "LEFT") and (cx + wid / 2) or (cx - wid / 2)
            posY = (vDir == "UP") and (cy - hgt / 2) or (cy + hgt / 2)
        end
        return corner, posX, posY, wid, hgt
    end

    PetKit.FreeAnchor = function(c, keySet)
        local corner, posX, posY = PetKit.FreeCorner(keySet, PetKit.Ctx())
        FB.FreePin(c, corner, posX, posY)
        return true
    end

    -- The Move Frames overlay places the spot of the tab it was opened on, which need not be the live one.
    PetKit.MoverSettings = function()
        return PetKit.Raw() and PetKit.View(PetKit.moverCtx or PetKit.Ctx())
    end

    -- Before the overlay shows: the live header, when up, takes the current settings.
    PetKit.MoverPrep = function()
        if PetKit.active and not InCombatLockdown() then
            PetKit.Layout()
            PetKit.Anchor()
        end
    end

    PetKit.PlaceMover = function(m, keySet)
        local corner, posX, posY, wid, hgt = PetKit.FreeCorner(keySet, PetKit.moverCtx or PetKit.Ctx())
        m:SetSize(wid, hgt)
        FB.FreePin(m, corner, posX, posY)
    end

    PetKit.SaveFreeRect = function(mover)
        FB.SaveMoverRect(mover, PetKit.MoverSettings())
    end

    -- ctx: "party" or "raid", the tab the overlay is for (the live one when nil).
    function mod.PF_SetMoverShown(show, context)
        if show then
            PetKit.moverCtx = context or PetKit.Ctx()
        end
        FB.SetMoverShown(PetKit, show, "ERFPetFramesMover", "Pet Frames")
    end

    -- ctx: true only when the overlay is up for that tab (any tab when nil).
    function mod.PF_IsMoverShown(context)
        return (PetKit.mover and PetKit.mover:IsShown() and (context == nil or PetKit.moverCtx == context)) or false
    end

    -- A size change on the tab whose overlay is up: the overlay takes the new size (the apply before
    -- this has already re-laid the live group).
    function mod.PF_PlaceMover(context)
        local m = PetKit.mover
        if not (m and m:IsShown() and PetKit.moverCtx == context) then
            return
        end
        local keySet = PetKit.MoverSettings()
        if not keySet then
            return
        end
        m:ClearAllPoints()
        PetKit.PlaceMover(m, keySet)
    end

    -- Options preview: made-up pets beside the preview frames, on the same visuals. Plain frames, built
    -- the first time a preview shows with Show Pets on; the preview code makes room and places them.
    PetKit.PV_PETS = {
        { name = "Felhunter", hp = 100 },
        { name = "Ghoul", hp = 64 },
        { name = "Spirit Beast", hp = 100 },
        { name = "Water Elemental", hp = 38 },
        { name = "Imp", hp = 85 },
    }
    PetKit.OPPOSITE = { RIGHT = "LEFT", LEFT = "RIGHT", DOWN = "UP", UP = "DOWN" }
    PetKit.pv = {}

    -- The settings the preview pets are painted with (their border reads it through FB.Source).
    PetKit.PvStyle = function()
        return PetKit.pvStyle
    end

    -- One preview pass's shared paint values (reused table). The texts are the frame's texts (no
    -- class for pets: a class colour mode reads white).
    PetKit.pvc = {}
    PetKit.PvColors = function(src)
        local c = PetKit.pvc
        PetKit.pvStyle = src
        c.texPath = ResolveHealthTexture(src)
        c.bgc = src.customBgColor or PetKit.DEFAULT_BG
        local rawValue = PetKit.Raw()
        c.hc = rawValue and rawValue.healthColor
        c.opacity = (src.healthBarOpacity or 100) / 100
        return c
    end

    -- Preview pet i at w x h, styled and painted (the caller places it).
    PetKit.PvFrame = function(index, hostFrame, src, wid, hgt, cfg, grouped)
        local frame = PetKit.pv[index]
        if not frame then
            frame = CreateFrame("Frame", nil, hostFrame)
            FB.BuildVisuals(frame, true)
            FB.src[frame] = PetKit.PvStyle
            PetKit.pv[index] = frame
        elseif frame:GetParent() ~= hostFrame then
            frame:SetParent(hostFrame)
        end
        frame:SetFrameStrata(hostFrame == UIParent and "HIGH" or hostFrame:GetFrameStrata())
        frame:SetSize(wid, hgt)
        local skinData = Inner.FFD[frame]
        if grouped and mod.RF_CompactOn(src, mod._partyPvActive == true) then
            skinData = GetFFD(frame)
            skinData._petGroupedPreview, skinData._petPreviewParty = true, mod._partyPvActive == true
        elseif skinData then
            skinData._petGroupedPreview = nil
        end
        FB.StyleVisuals(frame, src, wid, hgt, cfg.texPath, cfg.bgc)

        local pet = PetKit.PV_PETS[index]
        local pct = pet.hp
        local hc = cfg.hc
        frame._health:SetMinMaxValues(0, 100)
        -- pet.hp is a made-up plain number (PF.PV_PETS), so it is flipped here for an
        -- inverted fill (the _cuiInv stamp FB.StyleVisuals just left).
        frame._health:SetValue(frame._health._cuiInv and (100 - pct) or pct)
        frame._health:SetStatusBarColor(
            hc and hc.r or 23 / 255,
            hc and hc.g or 172 / 255,
            hc and hc.b or 49 / 255,
            cfg.opacity
        )
        -- The texts with the boss/pet rules: made-up health (3000 per percent) and a heal absorb
        -- of a quarter of it, in the raid preview's proportions.
        local st = FB.txs[frame]
        local pv = st._txPv or {}
        pv.hpPct, pv.hpPer, pv.ha, pv.name = pct, 3000, pct * 750, mod.CapName(pet.name, src)
        mod.RF_TextPreview(st, src, pv)
        frame:Show()
        return frame
    end

    -- Beside Owner preview: the pet size, side and gap as the real pets take them, the room it needs
    -- around the party frames (pads), and with Hide Self the slot after the last frame (sp: the party
    -- frames' spacing). s: the preview's view; w, h, sp: its party frame size and spacing.
    PetKit.OwnerPreviewSpec = function(src, wid, hgt, petSettings)
        local pw, ph, spacing = wid, hgt, petSettings
        if mod.RF_PartyKit() then
            pw, ph, spacing =
                PixelSnap(src.frameWidth or 125), PixelSnap(src.frameHeight or 60), PixelSnap(src.cellSpacing or -1)
        end
        local v = PetKit.View("party")
        pw = PixelSnap(math.max(10, pw + (v.extraWidth or 0)))
        ph = PixelSnap(math.max(10, ph + (v.extraHeight or 0)))
        local edgeSide, extra = PetKit.ResolveOwnerSide(src)
        spacing = spacing + PixelSnap(extra)
        local max = math.max
        local specInfo = {
            owner = true,
            w = pw,
            h = ph,
            side = edgeSide,
            gap = spacing,
            padL = 0,
            padT = 0,
            padR = 0,
            padB = 0,
        }
        if edgeSide == "right" then
            specInfo.padR, specInfo.padB = spacing + pw, max(0, ph - hgt)
        elseif edgeSide == "left" then
            specInfo.padL, specInfo.padB = spacing + pw, max(0, ph - hgt)
        elseif edgeSide == "below" then
            specInfo.padB, specInfo.padR = spacing + ph, max(0, pw - wid)
        else
            specInfo.padT, specInfo.padR = spacing + ph, max(0, pw - wid)
        end
        if src.partyHideSelf then
            local growDir = mod._PartyGrowth(src)
            specInfo.selfSlot = true
            -- The next slot: the party frames' pitch, party target frames along the stack included.
            petSettings = petSettings + mod.PT_AlongPitch(src, src.partyShowTargets == true)
            if growDir == "UP" then
                specInfo.sPt, specInfo.sRp, specInfo.sX, specInfo.sY = "BOTTOMLEFT", "TOPLEFT", 0, petSettings
                specInfo.padT, specInfo.padR = max(specInfo.padT, petSettings + ph), max(specInfo.padR, pw - wid)
            elseif growDir == "RIGHT" then
                specInfo.sPt, specInfo.sRp, specInfo.sX, specInfo.sY = "TOPLEFT", "TOPRIGHT", petSettings, 0
                specInfo.padR, specInfo.padB = max(specInfo.padR, petSettings + pw), max(specInfo.padB, ph - hgt)
            elseif growDir == "LEFT" then
                specInfo.sPt, specInfo.sRp, specInfo.sX, specInfo.sY = "TOPRIGHT", "TOPLEFT", -petSettings, 0
                specInfo.padL, specInfo.padB = max(specInfo.padL, petSettings + pw), max(specInfo.padB, ph - hgt)
            else
                specInfo.sPt, specInfo.sRp, specInfo.sX, specInfo.sY = "TOPLEFT", "BOTTOMLEFT", 0, -petSettings
                specInfo.padB, specInfo.padR = max(specInfo.padB, petSettings + ph), max(specInfo.padR, pw - wid)
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
    function mod.PF_PreviewSpec(party, src, wid, hgt, petSettings, boxW, boxH, ptSpec)
        local rawValue = PetKit.Raw()
        if not rawValue or rawValue[party and "party" or "raid"] ~= true then
            return
        end
        local keySet = PetKit.View(party and "party" or "raid")
        if keySet.position == "free" then
            return
        end
        if keySet.position == "owner" then
            if party then
                return PetKit.OwnerPreviewSpec(src, wid, hgt, petSettings)
            end
            return
        end
        local prior = keySet.position == "left"
        local spacing, growDir, edgeSide
        if party then
            spacing = src.groupSpacing or -1
            if mod.RF_PartyKit() then
                local extra
                prior, extra = mod.RF_KitAttach(src, prior)
                spacing = spacing + extra
            end
            spacing = spacing + mod.PT_PreviewReserve(ptSpec, src.partyHorizontal, prior)
            growDir = mod._PartyGrowth(src)
            if mod.RF_PartyKit() then
                wid, hgt, petSettings =
                    PixelSnap(src.frameWidth or 125),
                    PixelSnap(src.frameHeight or 60),
                    PixelSnap(src.cellSpacing or -1)
            else
                -- The party frames' pitch, party target frames along the stack included (PF.Layout's).
                petSettings = petSettings + mod.PT_AlongPitch(src, src.partyShowTargets == true)
            end
            if src.partyHorizontal then
                edgeSide = prior and "UP" or "DOWN"
            else
                edgeSide = prior and "LEFT" or "RIGHT"
            end
        else
            spacing = mod.RF_GroupSpacing(src)
            growDir = src.unitGrowth or "DOWN"
            edgeSide = src.groupGrowth or "RIGHT"
            -- The grid flow ends in the rightmost column too, so the pets hang off
            -- the same edge a plain RIGHT run uses -- FB.Anchor agrees. Read raw,
            -- PF.OPPOSITE would return nil for it and the side would fall through
            -- to the vertical branch, drawing the pets above the groups.
            if edgeSide == "DOWNRIGHT" then
                edgeSide = "RIGHT"
            end
            if prior then
                edgeSide = PetKit.OPPOSITE[edgeSide]
            end
        end

        local specInfo = { n = party and 3 or 5, sp = petSettings, grow = growDir, before = prior }
        specInfo.w = PixelSnap(math.max(10, wid + (keySet.extraWidth or 0)))
        specInfo.h = PixelSnap(math.max(10, hgt + (keySet.extraHeight or 0)))
        if growDir == "RIGHT" or growDir == "LEFT" then
            specInfo.bw, specInfo.bh = specInfo.n * specInfo.w + (specInfo.n - 1) * petSettings, specInfo.h
        else
            specInfo.bw, specInfo.bh = specInfo.w, specInfo.n * specInfo.h + (specInfo.n - 1) * petSettings
        end
        specInfo.ox, specInfo.oy = 0, 0
        -- Party stacks that grow up or left start at the box's bottom or right edge.
        if party and growDir == "UP" then
            specInfo.oy = specInfo.bh - boxH
        end
        if party and growDir == "LEFT" then
            specInfo.ox = boxW - specInfo.bw
        end
        if edgeSide == "RIGHT" then
            specInfo.ox = boxW + spacing
        elseif edgeSide == "LEFT" then
            specInfo.ox = -spacing - specInfo.bw
        elseif edgeSide == "DOWN" then
            specInfo.oy = -(boxH + spacing)
        else
            specInfo.oy = spacing + specInfo.bh
        end
        return specInfo
    end

    -- Shows the spec's pets with the group's top-left at x, y from rel's top-left. s: the settings they
    -- are styled from.
    function mod.PF_ShowPreview(specInfo, src, hostFrame, rel, posX, posY)
        local color = PetKit.PvColors(src)
        for index = 1, specInfo.n do
            local frame = PetKit.PvFrame(index, hostFrame, src, specInfo.w, specInfo.h, color, true)
            local off = index - 1
            local fx, fy = posX, posY
            if specInfo.grow == "RIGHT" then
                fx = posX + off * (specInfo.w + specInfo.sp)
            elseif specInfo.grow == "LEFT" then
                fx = posX + specInfo.bw - specInfo.w - off * (specInfo.w + specInfo.sp)
            elseif specInfo.grow == "UP" then
                fy = posY - specInfo.bh + specInfo.h + off * (specInfo.h + specInfo.sp)
            else
                fy = posY - off * (specInfo.h + specInfo.sp)
            end
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", rel, "TOPLEFT", fx, fy)
        end
        for index = specInfo.n + 1, #PetKit.pv do
            PetKit.pv[index]:Hide()
        end
        mod.RF_PreviewPetCompact(PetKit.pv, src, mod._partyPvActive == true, specInfo.grow)
    end

    -- Beside Owner preview: a pet beside each shown party preview frame, and with Hide Self one after
    -- lastF (the last frame along the growth). s: the settings they are styled from.
    function mod.PF_ShowOwnerPreview(specInfo, src, hostFrame, lastF)
        mod.RF_PreviewPetCompact(nil)
        local color = PetKit.PvColors(src)
        local num = 0
        for index = 1, 5 do
            local owner = mod._partyPvFrames[index]
            if owner and owner:IsShown() then
                num = num + 1
                local frame = PetKit.PvFrame(num, hostFrame, src, specInfo.w, specInfo.h, color)
                frame:ClearAllPoints()
                PetKit.OwnerPoint(frame, owner, specInfo.side, specInfo.gap)
            end
        end
        if specInfo.selfSlot and lastF and num < #PetKit.PV_PETS then
            num = num + 1
            local frame = PetKit.PvFrame(num, hostFrame, src, specInfo.w, specInfo.h, color)
            frame:ClearAllPoints()
            frame:SetPoint(specInfo.sPt, lastF, specInfo.sRp, specInfo.sX, specInfo.sY)
        end
        for index = num + 1, #PetKit.pv do
            PetKit.pv[index]:Hide()
        end
    end

    function mod.PF_HidePreview()
        mod.RF_PreviewPetCompact(nil)
        for _, frame in ipairs(PetKit.pv) do
            frame:Hide()
        end
    end

    -- Real-frame previews hide the real frames by alpha; while they do, our own mouse blockers keep the
    -- invisible pet buttons from taking clicks: one over the pet header, and one on each Beside Owner
    -- pet (they sit outside the party frames' blocker). Our frames, so Hide() is combat-legal.
    PetKit.SetPreviewBlock = function(enabled)
        PetKit.pvBlockOn = enabled or nil
        local heading = PetKit.container
        if enabled and PetKit.active and heading then
            local block = PetKit.hdrBlock
            if not block then
                -- Under the header's parent, so it hides with the header's pet-battle and solo hide.
                block = CreateFrame("Frame", nil, PetKit.hider)
                block:EnableMouse(true)
                PetKit.hdrBlock = block
            end
            block:SetAllPoints(heading)
            block:SetFrameStrata(heading:GetFrameStrata())
            block:SetFrameLevel(heading:GetFrameLevel() + 50)
            block:Show()
        elseif PetKit.hdrBlock then
            PetKit.hdrBlock:Hide()
        end
        for _, petBtn in ipairs(PetKit.ownerButtons) do
            local block = PetKit.pvBlock[petBtn]
            if enabled and PetKit.ownerActive then
                if not block then
                    block = CreateFrame("Frame", nil, petBtn)
                    block:SetAllPoints(petBtn)
                    block:EnableMouse(true)
                    PetKit.pvBlock[petBtn] = block
                end
                block:SetFrameLevel(petBtn:GetFrameLevel() + 50)
                block:Show()
            elseif block then
                block:Hide()
            end
        end
    end
    mod._PF_SetPreviewBlock = PetKit.SetPreviewBlock

    -- A frame strata change while blocked: re-seat the blockers.
    function mod._PF_RefreshPreviewBlock()
        if PetKit.pvBlockOn then
            PetKit.SetPreviewBlock(true)
        end
    end

    -- The header's placement. FB.Anchor remembers the group it followed in PF.chainTgt (none on Free
    -- Move), which the Friendly Boss / Extra Frames probe compares against. A combat call is deferred
    -- to the combat-end flush by FB.Anchor.
    PetKit.Anchor = function()
        PetKit.attachParty = PetKit.PartyMode()
        if not InCombatLockdown() then
            PetKit.chainTgt = false
        end
        FB.Anchor(PetKit)
    end

    function mod.PF_ReAnchor()
        if not InCombatLockdown() then
            PetKit.anchorDirty = nil
        end
        PetKit.PlaceSelfPet()
        if PetKit.active then
            PetKit.Anchor()
        end
    end

    -- Friendly Boss and Extra Frames can appear, move or go away without a roster change. A group that
    -- moves carries the pets chained after it along, so the header re-anchors only when the group it
    -- follows changes.
    PetKit.ProbeChain = function()
        if not PetKit.active then
            return
        end
        local keySet = PetKit.Settings()
        if not keySet or keySet.position == "free" then
            return
        end
        if (PetKit.ChainAnchor(keySet) or false) ~= PetKit.chainTgt then
            PetKit.Anchor()
        end
    end

    -- The party layout pass (size, growth, spacing, orientation, the party frames' show/hide edge, the
    -- kit's clearance): re-lays the pets and the party target frames that sit beside the party frames,
    -- delta-gated. The target frames go after the Beside Owner pets they follow and before any
    -- anchoring, so the attached groups are pinned once, on the new reserve.
    function mod.PF_PartyRelayout()
        if not InCombatLockdown() then
            if PetKit.active and PetKit.PartyMode() then
                PetKit.Layout()
            end
            if PetKit.ownerActive then
                PetKit.OwnerLayout()
                PetKit.SetOwnerWatch()
            end
        end
        mod._PT_Layout()
        mod.PF_ReAnchor()
    end

    -- A party settings reload, which owns the pets styled from the party settings (the Beside Owner pets,
    -- and the header beside the party frames): they check their style (restyled only when it changed)
    -- and repaint. Deferred through combat to the combat-end flush.
    function mod.PF_PartyRestyle()
        local header = PetKit.active and PetKit.PartyMode()
        if not (header or PetKit.ownerActive) then
            PetKit.partyRestyleDirty = nil
            return
        end
        if InCombatLockdown() then
            PetKit.partyRestyleDirty = true
            return
        end
        PetKit.partyRestyleDirty = nil
        if PetKit.ownerActive then
            PetKit.OwnerLayout(true)
            PetKit.RepaintShown(PetKit.ownerButtons)
        end
        if header then
            PetKit.Layout(true)
        end
        PetKit.SyncListeners()
    end

    -- Master apply: the options, the raid frames' reloads and the roster flush (below). OOC only;
    -- deferred through combat like the other groups. restyle: a raid settings or profile reload, which
    -- restyles only the pets styled from the raid settings (the party reload that follows it restyles
    -- the others, see ns.PF_PartyRestyle).
    function mod.PF_Apply(needsRestyle)
        if not saved or not saved.profile then
            return
        end
        local rawValue = PetKit.Raw()
        if not rawValue then
            return
        end
        if InCombatLockdown() then
            PetKit.applyDirty = true
            PetKit.restyleDirty = PetKit.restyleDirty or needsRestyle
            return
        end
        -- This pass covers a roster change or a combat-deferred apply still waiting for the flush.
        needsRestyle = needsRestyle or PetKit.restyleDirty
        PetKit.dirty, PetKit.applyDirty, PetKit.restyleDirty = nil, nil, nil

        -- Beside Owner. Chosen before the party frames exist (early login), neither kind comes up: the
        -- next apply brings the pets up. Only their activation edge checks their style here, before
        -- they show (and paint as they do).
        local chosen = PetKit.OwnerChosen()
        local ownerFrame = chosen and mod._partySelfButton ~= nil
        if ownerFrame then
            local edge = not PetKit.ownerActive
            if edge then
                PetKit.EnsureOwnerBuilt()
                PetKit.ownerActive = true
                PetKit.SetOwnerLinks(true)
            end
            PetKit.OwnerLayout(edge)
            PetKit.SetOwnerWatch()
            PetKit.SetTracking(true)
            if edge then
                PetKit.NotifyReserve()
            end
        elseif PetKit.ownerActive then
            PetKit.ownerActive = nil
            PetKit.SetOwnerLinks(false)
            PetKit.SetOwnerWatch()
            PetKit.NotifyReserve()
        end

        if chosen or not PetKit.Wanted() or not PetKit.EnsureBuilt() then
            PetKit.active = nil
            mod.RF_SyncPetCompact()
            PetKit.chainTgt = nil
            if PetKit.built then
                PetKit.container:Hide()
            end
            PetKit.ClearHider()
            if not ownerFrame then
                PetKit.SetTracking(false)
            end
            if PetKit.pvBlockOn then
                PetKit.SetPreviewBlock(true)
            end
            PetKit.SyncListeners()
            return
        end

        -- The activation edge checks the style too: settings can change while the header is down.
        local edge = not PetKit.active
        PetKit.active = true
        PetKit.SetTracking(true)
        -- Layout also registers the parent's hide (PF.SetHider) and repaints the pets on screen on a
        -- restyle; the header shows last, laid out, its pets painting as they show. The roster's own
        -- re-assignments paint in the buttons' unit hook.
        PetKit.Layout((needsRestyle and PetKit.Ctx() == "raid") or edge)
        mod.PF_ReAnchor()
        if not PetKit.container:IsShown() then
            PetKit.container:Show()
        end
        if PetKit.pvBlockOn then
            PetKit.SetPreviewBlock(true)
        end
        PetKit.SyncListeners()
    end

    -- Roster and zoning edges, folded into the raid frames' own passes: the roster change and the zone-in
    -- mark the pets dirty (in combat too), and the raid frames' roster pass, zone-in settle and combat
    -- end each flush once, after their own layout. Both toggles off, nothing is marked.
    function mod.PF_MarkDirty()
        local rawValue = PetKit.Raw()
        if rawValue and (rawValue.party == true or rawValue.raid == true) then
            PetKit.dirty = true
        end
    end

    -- Runs what is waiting: a marked or combat-deferred apply, a combat-deferred party restyle, then a
    -- combat-deferred placement. OOC only; in combat everything stays marked for the combat-end flush.
    function mod.PF_Flush()
        if InCombatLockdown() then
            return
        end
        if PetKit.dirty or PetKit.applyDirty then
            mod.PF_Apply()
        end
        if PetKit.partyRestyleDirty then
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
        if PetKit.anchorDirty then
            mod.PF_ReAnchor()
        end
    end

    hooksecurefunc(mod, "FB_Apply", PetKit.ProbeChain)
    hooksecurefunc(mod, "XF_Apply", PetKit.ProbeChain)

    -- Target, pet and vehicle listeners; each is registered only while pets that need it are on screen
    -- (PF.SyncShownEvents).
    do
        local eventFrame = mod.TakeShell()
        eventFrame:SetScript("OnEvent", function(_, evt, unitToken)
            if not saved then
                return
            end
            if evt == "PLAYER_TARGET_CHANGED" then
                PetKit.EachShown(PetKit.TargetFlip)
            else -- UNIT_PET / UNIT_ENTERED_VEHICLE / UNIT_EXITED_VEHICLE
                PetKit.OnPetChanged(unitToken)
            end
        end)
        PetKit.eventFrame = eventFrame
    end
end -- PF scope block

Inner.broken = false
