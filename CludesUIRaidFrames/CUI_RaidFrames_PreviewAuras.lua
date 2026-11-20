if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_RaidFrames_PreviewAuras.lua
--
--  The preview aura cycling: the active-preview resolvers, the effective-value
--  overlay, and the ticker that places fake debuffs and defensives.
--  Reads the earlier preview files through ns and ns._previewInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._previewInternals
-- CUI_RaidFrames_Preview.lua or an earlier preview file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local type = type
local C_Timer = C_Timer

local RF = mod._internals -- the table of the Raid Frames chain
local PixelSnap = RF.PixelSnap

local previewClassTokens, previewFrames = Inner.previewClassTokens, Inner.previewFrames

-- Shared state from the raid-frame and preview chains.
local saved
RF.dbSetters[#RF.dbSetters + 1] = function(val)
    saved = val
end
local previewActive = false
Inner.previewActiveSetters[#Inner.previewActiveSetters + 1] = function(val)
    previewActive = val
end

-------------------------------------------------------------------------------
--  Preview aura cycling system
--  Manages fake debuffs/defensives on preview frames with real durations.
--  Maintains at least 1 per group for each enabled category.
-------------------------------------------------------------------------------
local pvAuraTicker = nil

-- Active-preview resolvers: the shared aura/animation tickers serve BOTH the
-- raid preview (previewFrames / previewActive) and the party preview
-- (ns._partyPvFrames / ns._partyPvActive). Keying off ns._partyPvActive at call
-- time lets one code path drive whichever preview is currently on screen.
local function PvFrames()
    return (mod._partyPvActive and mod._partyPvFrames) or previewFrames
end
local function PvActive()
    return previewActive or mod._partyPvActive
end
-- Party preview reads party-scaled / party-prefixed settings so aura icons match
-- the party frames (size, position, colors); raid preview reads the live profile
-- through the real-preview effective overlay (below) so an open panel's view
-- swap never leaks into the preview.
local function PvSettings()
    return (mod._partyPvActive and mod._scaledPartyProxy) or mod._pvOverlayProxy or saved.profile
end
-- Class tokens for icon selection: ApplyPartyPreviewData hands the party tokens
-- to ApplyPreviewData only, so the ticker must resolve them itself.
local function PvClassTokens()
    return (mod._partyPvActive and mod._partyPvCT) or previewClassTokens
end

-------------------------------------------------------------------------------
--  Real-preview effective-value overlay: while the options panel holds a
--  value-swapped VIEW (Default Editing Mode or an editing-as session) and
--  preview mode is "real", preview reads must resolve the CURRENT SPEC's
--  panel-closed effective values (spec override, else applied conditional,
--  else defaults) -- never the view's swapped live values. The overlay is a
--  read-through proxy: captured RF keys resolve from the override stores,
--  everything else falls through to live db.profile, so options widgets
--  (which read live directly) keep showing the view. Rebuilt event-driven at
--  preview refresh entry points and the module-refresh tail; nil when no view
--  swap is active (byte-identical reads outside editing views). ZERO writes to
--  live/override stores.
-------------------------------------------------------------------------------
do
    local proxy
    local proxyMT = {
        __index = function(_, key)
            local shade = mod._pvOverlay
            if shade ~= nil then
                local val = shade[key]
                if val ~= nil then
                    if val == CludesUI.SPECOV_NIL then
                        return nil
                    end
                    return val
                end
            end
            return saved.profile[key]
        end,
    }
    -- Segment-key resolution mirrors the value system's live walk: prefer
    -- the string key when the table holds it, else numeric.
    local function SegKey(tbl, seg)
        if tbl[seg] ~= nil then
            return seg
        end
        local num = tonumber(seg)
        if num ~= nil and tbl[num] ~= nil then
            return num
        end
        return seg
    end

    function mod._RebuildPvOverlay()
        local isActive = (saved.profile.previewMode == "real")
            and CludesUI.SpecOverrides_ViewActive()
            and CludesUI.SpecOverrides_PeekEffectiveValues
        local flat, specSrc, condSrc
        if isActive then
            flat, specSrc, condSrc = CludesUI.SpecOverrides_PeekEffectiveValues("CludesUIRaidFrames")
        end
        if not flat then
            mod._pvOverlay = nil
            mod._pvOverlayProxy = nil
            if mod._RefreshProxyModes then
                mod._RefreshProxyModes()
            end
            mod._pvOverlaySrc = nil
            if mod._UpdatePvModeChrome then
                mod._UpdatePvModeChrome()
            end
            return
        end
        local NIL_SENT = CludesUI.SPECOV_NIL
        local overlayFrame = {}
        for fkey, val in pairs(flat) do
            local filePath = fkey:match("^[^\31]+\31(.*)$")
            if filePath and filePath ~= "" then
                local segs = { strsplit("\30", filePath) }
                if #segs == 1 then
                    -- Depth-1: NIL_SENT stays encoded; the proxy decodes it.
                    overlayFrame[SegKey(saved.profile, segs[1])] = val
                else
                    -- Deeper path: shallow-clone the LIVE parent chain along
                    -- the path once, then set (or remove) the leaf -- sibling
                    -- keys inside the cloned subtable keep their live values.
                    local liveT = saved.profile
                    local dstParent = overlayFrame
                    local success = true
                    for index = 1, #segs - 1 do
                        local k = SegKey(liveT, segs[index])
                        local liveChild = liveT[k]
                        if type(liveChild) ~= "table" then
                            success = false
                            break
                        end
                        local dstChild = dstParent[k]
                        -- A shallow parent copy still shares its live children.
                        -- Detach each shared child before writing preview values.
                        if type(dstChild) ~= "table" or dstChild == liveChild then
                            dstChild = {}
                            for ck, cv in pairs(liveChild) do
                                dstChild[ck] = cv
                            end
                            dstParent[k] = dstChild
                        end
                        dstParent = dstChild
                        liveT = liveChild
                    end
                    if success then
                        local lk = SegKey(liveT, segs[#segs])
                        if val == NIL_SENT then
                            dstParent[lk] = nil
                        else
                            dstParent[lk] = val
                        end
                    end
                end
            end
        end
        mod._pvOverlay = overlayFrame
        if not proxy then
            proxy = setmetatable({}, proxyMT)
        end
        mod._pvOverlayProxy = proxy
        if mod._RefreshProxyModes then
            mod._RefreshProxyModes()
        end
        mod._pvOverlaySrc = { spec = specSrc, cond = condSrc }
        if mod._UpdatePvModeChrome then
            mod._UpdatePvModeChrome()
        end
    end

    -- The preview-path settings accessor: overlay proxy while a view swap
    -- is active in real preview mode, else the live profile itself.
    function mod.PvEffectiveProfile()
        return mod._pvOverlayProxy or saved.profile
    end

    -- Session unlock-layer element lookup: while an override session with a
    -- CUSTOM unlock mode is being edited in real preview mode, the preview
    -- mirrors that session's unlock positions -- the layer's recorded elem
    -- for the key, baseline fallback per element. nil in every other state
    -- (live positioning, today's behavior). Anchored containers resolve to
    -- their recorded bookkeeping coordinates, not a live anchor chain.
    function mod._PvSessionElem(key)
        if saved.profile.previewMode ~= "real" then
            return nil
        end
        local layer, base
        local sfn = CludesUI.SpecOverrides_EditSessionUnlockLayer
        if sfn then
            layer, base = sfn()
        end
        if not layer then
            -- Default view: mirror the REAL spec's RESOLVED effective fork. Never the
            -- live pointer (s.active) -- it lags membership and unlock-mode edits made
            -- while the panel is open, and the preview must show the layer that WOULD
            -- apply on exit. Baseline-effective specs return nil here -> live
            -- positioning, byte-identical to before the feature.
            local vfn = CludesUI.SpecOverrides_ViewActive
            if vfn and vfn() and CludesUI.SpecOverrides_EffectiveUnlockLayer then
                layer, base = CludesUI.SpecOverrides_EffectiveUnlockLayer()
            end
        end
        if not layer then
            return nil
        end
        local e = layer.elems and layer.elems[key]
        if not e and base and base ~= layer then
            e = base.elems and base.elems[key]
        end
        return e
    end
end

local function PvAuraGetGroup(index)
    return math.ceil(index / 5)
end

-- Pick a random icon for the given type and frame index
local function PvAuraPickIcon(auraType, frameIndex)
    if auraType == "def" then
        local s2 = PvSettings()
        local showDef = s2 and s2.showDefensives
        local showExt = s2 and s2.showExternals
        local pool = {}
        local ct = PvClassTokens()[frameIndex] or "WARRIOR"
        if showDef then
            local ci = mod._PV_DEF_ICONS[ct]
            if ci then
                for _, ic in ipairs(ci) do
                    pool[#pool + 1] = ic
                end
            end
        end
        if showExt then
            for _, ic in ipairs(mod._PV_EXT_ICONS) do
                pool[#pool + 1] = ic
            end
        end
        if #pool == 0 then
            return nil
        end
        return pool[math.random(#pool)]
    else
        return mod._PV_DEBUFF_ICONS[math.random(#mod._PV_DEBUFF_ICONS)]
    end
end

-- Position a preview aura icon on a frame (reuses anchor logic)
local function PvAuraAnchor(iconTex, frame, auraType, slot, totalShown)
    local s2 = PvSettings()

    -- Debuffs use the shared grid layout (same DebuffGridPoint helper as the live
    -- frames) so the preview matches exactly -- including row wrapping and CENTER
    -- per-row centering. `slot` is the 0-based index among visible icons.
    if auraType ~= "def" then
        local sz = mod.RFC_DebuffSize(s2)
        iconTex:SetSize(sz, sz)
        iconTex:ClearAllPoints()
        local corner, fx, fy = mod.DebuffGridPoint(s2, slot, totalShown)
        iconTex:SetPoint(corner, mod.RF_AnchorHost(frame._health, s2), corner, fx, fy)
        return
    end

    -- Defensives: single-line relative chaining (no wrapping).
    local place, ox, oy, grow, sz, spc
    place = s2.defPosition or "center"
    ox = s2.defOffsetX or 0
    oy = s2.defOffsetY or 0
    grow = s2.defGrowDirection or "CENTER"
    sz = s2.defSize or 22
    spc = PixelSnap(s2.defSpacing or 1)
    local spacing = sz + spc
    local centerOff = 0
    if grow == "CENTER" and totalShown > 0 then
        centerOff = -((totalShown - 1) * spacing) / 2
    end
    iconTex:SetSize(sz, sz)
    iconTex:ClearAllPoints()
    if slot == 0 then
        local fx = ox + (grow == "CENTER" and centerOff or 0)
        -- All aura icon previews (debuffs, defensives) anchor flush
        -- to the health bar edge -- no 1px inset -- matching the real frames.
        local pvHost = mod.RF_AnchorHost(frame._health, s2)
        if place == "topleft" then
            iconTex:SetPoint("TOPLEFT", pvHost, "TOPLEFT", fx, oy)
        elseif place == "top" then
            iconTex:SetPoint("TOP", pvHost, "TOP", fx, oy)
        elseif place == "topright" then
            iconTex:SetPoint("TOPRIGHT", pvHost, "TOPRIGHT", fx, oy)
        elseif place == "left" then
            iconTex:SetPoint("LEFT", pvHost, "LEFT", fx, oy)
        elseif place == "center" then
            iconTex:SetPoint("CENTER", pvHost, "CENTER", fx, oy)
        elseif place == "right" then
            iconTex:SetPoint("RIGHT", pvHost, "RIGHT", fx, oy)
        elseif place == "bottomright" then
            iconTex:SetPoint("BOTTOMRIGHT", pvHost, "BOTTOMRIGHT", fx, oy)
        elseif place == "bottom" then
            iconTex:SetPoint("BOTTOM", pvHost, "BOTTOM", fx, oy)
        else
            iconTex:SetPoint("BOTTOMLEFT", pvHost, "BOTTOMLEFT", fx, oy)
        end
    else
        -- Chain from previous icon in same pool
        local pool = frame._pvDefs
        local previous = pool[slot] -- slot is 0-based; current is slot+1, prev is pool[slot]
        if previous and previous:IsShown() then
            if grow == "RIGHT" or grow == "CENTER" then
                iconTex:SetPoint("LEFT", previous, "RIGHT", spc, 0)
            elseif grow == "LEFT" then
                iconTex:SetPoint("RIGHT", previous, "LEFT", -spc, 0)
            elseif grow == "UP" then
                iconTex:SetPoint("BOTTOM", previous, "TOP", 0, spc)
            elseif grow == "DOWN" then
                iconTex:SetPoint("TOP", previous, "BOTTOM", 0, -spc)
            end
        end
    end
end

-- Apply a fake aura to a preview frame slot
local function PvAuraApply(frameIndex, auraType, slotIndex)
    local frame = PvFrames()[frameIndex]
    if not frame or not frame._health then
        return
    end
    local pool = auraType == "def" and frame._pvDefs or frame._pvDebuffs
    local iconTex = pool and pool[slotIndex]
    if not iconTex then
        return
    end

    local texture = PvAuraPickIcon(auraType, frameIndex)
    if not texture then
        iconTex:Hide()
        return
    end

    local s2 = PvSettings()
    local dur = 8 + math.random() * 4 -- 8-12 seconds
    local startTime = GetTime()

    iconTex._tex:SetTexture(texture)
    if auraType == "db" then
        local _z = s2.debuffIconZoom or 0.08
        iconTex._tex:SetTexCoord(_z, 1 - _z, _z, 1 - _z)
    elseif auraType == "def" then
        local _z = s2.defIconZoom or 0.08
        iconTex._tex:SetTexCoord(_z, 1 - _z, _z, 1 - _z)
    end
    if iconTex._cooldown then
        local showSwipe, showDurText, dtColor, dtSize, dtOX, dtOY
        if auraType == "db" then
            showSwipe = s2.debuffShowSwipe ~= false
            showDurText = s2.debuffShowDurText
            dtColor = s2.debuffDurTextColor or { r = 1, g = 1, b = 1 }
            dtSize = s2.debuffDurTextSize or 8
            dtOX = s2.debuffDurTextOffsetX or 0
            dtOY = s2.debuffDurTextOffsetY or 0
        else
            showSwipe = s2.defShowSwipe ~= false
            showDurText = s2.defShowDurText
            dtColor = s2.defDurTextColor or { r = 1, g = 1, b = 1 }
            dtSize = s2.defDurTextSize or 8
            dtOX = s2.defDurTextOffsetX or 0
            dtOY = s2.defDurTextOffsetY or 0
        end
        iconTex._cooldown:SetCooldown(startTime, dur)
        iconTex._cooldown:SetDrawSwipe(showSwipe)
        iconTex._cooldown:SetHideCountdownNumbers(not showDurText)
        iconTex._cooldown:Show()

        -- Style the built-in countdown text via GetCountdownFontString
        if showDurText and dtColor then
            local cdText = iconTex._cooldown.GetCountdownFontString and iconTex._cooldown:GetCountdownFontString()
            if cdText then
                local fontFile = (CludesUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
                CludesUI.ApplyIconTextFont(cdText, fontFile, dtSize, "raidFrames")
                cdText:SetTextColor(dtColor.r, dtColor.g, dtColor.b)
                cdText:ClearAllPoints()
                cdText:SetPoint("CENTER", iconTex, "CENTER", dtOX, dtOY)
            end
        end
    end

    -- Border
    if auraType == "def" then
        mod.RFC_PreviewAuraBorder(iconTex, iconTex._borderFrame, s2, "defBorder")
    else
        mod.RFC_PreviewAuraBorder(iconTex, iconTex._borderFrame, s2, "debuffBorder")
    end

    -- Stacks text (debuffs only: show "2" on exactly one random debuff)
    if iconTex._count then
        iconTex._count:SetText("")
    end

    iconTex:Show()

    -- Track expiration
    local key = frameIndex .. ":" .. auraType .. ":" .. slotIndex
    mod._pvActiveAuras[key] =
        { frameIndex = frameIndex, auraType = auraType, slot = slotIndex, expTime = startTime + dur }
end

-- Count active auras of a type in a group (optionally skip slots below minSlot)
local function PvAuraCountInGroup(set, auraType, minSlot)
    minSlot = minSlot or 1
    local total = 0
    for _, details in pairs(mod._pvActiveAuras) do
        if
            details.auraType == auraType
            and details.slot >= minSlot
            and PvAuraGetGroup(details.frameIndex) == set
            and details.expTime > GetTime()
        then
            total = total + 1
        end
    end
    return total
end

-- Pick a random frame in a group that doesn't have a random aura of this type
-- (ignores permanent slot 1 debuffs so random debuffs can still be assigned)
local function PvAuraPickFrame(set, auraType, minSlot)
    minSlot = minSlot or 1
    local candidates = {}
    local popFrame = PvFrames()
    local startIdx = (set - 1) * 5 + 1
    local endIdx = set * 5
    for index = startIdx, endIdx do
        if index <= #popFrame and popFrame[index] then
            local hasType = false
            for _, details in pairs(mod._pvActiveAuras) do
                if
                    details.frameIndex == index
                    and details.auraType == auraType
                    and details.slot >= minSlot
                    and details.expTime > GetTime()
                then
                    hasType = true
                    break
                end
            end
            if not hasType then
                candidates[#candidates + 1] = index
            end
        end
    end
    if #candidates == 0 then
        return nil
    end
    return candidates[math.random(#candidates)]
end

-- Re-anchor all visible icons on a frame for CENTER growth
local function PvAuraReanchorFrame(frameIndex, auraType)
    local frame = PvFrames()[frameIndex]
    if not frame then
        return
    end
    local pool = auraType == "def" and frame._pvDefs or frame._pvDebuffs
    if not pool then
        return
    end
    local isShown = 0
    for _, ic in ipairs(pool) do
        if ic:IsShown() then
            isShown = isShown + 1
        end
    end
    local slotIdx = 0
    for _, ic in ipairs(pool) do
        if ic:IsShown() then
            PvAuraAnchor(ic, frame, auraType, slotIdx, isShown)
            slotIdx = slotIdx + 1
        end
    end
end

local function PvAuraTick()
    if not PvActive() then
        return
    end
    local nowTime = GetTime()
    local s2 = PvSettings()
    local wantDef = mod._defensivesPreviewVisible and (s2.showDefensives or s2.showExternals)
    local wantDb = mod._debuffsPreviewVisible and s2.debuffFilter ~= "none"

    -- Expire finished auras. In Real/Overlay preview the random per-player auras
    -- (defensives and random debuffs in slot 2+) loop on the SAME frame with a fresh
    -- duration instead of being removed -- otherwise the per-group top-up below
    -- re-picks a new random player every cycle, so icons appear to "jump" between
    -- players. Full Preview (test mode) keeps rotating. The raid-wide pulse debuff (db
    -- slot 1) is never looped here; it hits every frame at once on its own pulse cycle.
    local loopSame = not mod._testMode
    for key, details in pairs(mod._pvActiveAuras) do
        if key ~= "_stackKey" and key ~= "raidwide:db" and details.expTime and details.expTime <= nowTime then
            local isRandom = details.auraType == "def" or (details.auraType == "db" and details.slot >= 2)
            if loopSame and isRandom then
                -- Re-spawn on the same frame/slot (overwrites this same key, so the
                -- group count stays put and no new player is chosen). If it held the
                -- stacks marker, drop it so the stacks pass re-applies the count text.
                if mod._pvActiveAuras._stackKey == key then
                    mod._pvActiveAuras._stackKey = nil
                end
                PvAuraApply(details.frameIndex, details.auraType, details.slot)
                PvAuraReanchorFrame(details.frameIndex, details.auraType)
            else
                local frame = PvFrames()[details.frameIndex]
                if frame then
                    local pool = details.auraType == "def" and frame._pvDefs or frame._pvDebuffs
                    local ic = pool and pool[details.slot]
                    if ic then
                        ic:Hide()
                        if ic._cooldown then
                            ic._cooldown:Clear()
                        end
                        if ic._count then
                            ic._count:SetText("")
                        end
                    end
                end
                if mod._pvActiveAuras._stackKey == key then
                    mod._pvActiveAuras._stackKey = nil
                end
                mod._pvActiveAuras[key] = nil
            end
        end
    end

    -- Raid-wide debuff pulse: 10s debuff on ALL frames, cycling every 25s
    if wantDb then
        -- Check if the raid-wide pulse is active or needs to start/restart
        local pulseKey = "raidwide:db"
        local pulseInfo = mod._pvActiveAuras[pulseKey]
        if not pulseInfo then
            -- First tick or after expiry gap: schedule next pulse
            mod._pvActiveAuras[pulseKey] = { nextPulse = nowTime, active = false }
            pulseInfo = mod._pvActiveAuras[pulseKey]
        end
        if pulseInfo.active and pulseInfo.expTime and pulseInfo.expTime <= nowTime then
            -- Pulse expired: hide slot 1 on all frames. While wrapping is on,
            -- skip the player frame (index 1) -- it's a dedicated full showcase
            -- (filled below) so its slots stay put instead of pulsing.
            local popFrame = PvFrames()
            for fi = (((s2.debuffPerRow or 1) > 1) and 2 or 1), #popFrame do
                local frame = popFrame[fi]
                if frame and frame._pvDebuffs and frame._pvDebuffs[1] then
                    frame._pvDebuffs[1]:Hide()
                    if frame._pvDebuffs[1]._cooldown then
                        frame._pvDebuffs[1]._cooldown:Clear()
                    end
                    -- Re-pack remaining debuffs so a surviving slot-2+ icon shifts
                    -- into the vacated first position immediately, instead of only
                    -- when that icon itself refreshes.
                    PvAuraReanchorFrame(fi, "db")
                end
                mod._pvActiveAuras[fi .. ":db:1"] = nil
            end
            pulseInfo.active = false
            pulseInfo.nextPulse = nowTime + 15 -- 15s gap before next pulse
        end
        if not pulseInfo.active and nowTime >= (pulseInfo.nextPulse or 0) then
            -- Apply 10s debuff to all frames (skip the player showcase frame 1
            -- while wrapping is on; it owns its own debuff slots, filled below).
            local dur = 10
            local popFrame = PvFrames()
            for fi = (((s2.debuffPerRow or 1) > 1) and 2 or 1), #popFrame do
                local key = fi .. ":db:1"
                local frame = popFrame[fi]
                if frame and frame._pvDebuffs and frame._pvDebuffs[1] and frame._health then
                    local iconTex = frame._pvDebuffs[1]
                    iconTex._tex:SetTexture(5927657)
                    local _z = s2.debuffIconZoom or 0.08
                    iconTex._tex:SetTexCoord(_z, 1 - _z, _z, 1 - _z)
                    iconTex:SetSize(mod.RFC_DebuffSize(s2), mod.RFC_DebuffSize(s2))
                    if iconTex._cooldown then
                        iconTex._cooldown:SetCooldown(nowTime, dur)
                        iconTex._cooldown:SetDrawSwipe(s2.debuffShowSwipe ~= false)
                        iconTex._cooldown:SetHideCountdownNumbers(not s2.debuffShowDurText)
                        iconTex._cooldown:Show()
                        if s2.debuffShowDurText then
                            local cdText = iconTex._cooldown.GetCountdownFontString
                                and iconTex._cooldown:GetCountdownFontString()
                            if cdText then
                                local dtc = s2.debuffDurTextColor or { r = 1, g = 1, b = 1 }
                                local fp = (CludesUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
                                CludesUI.ApplyIconTextFont(
                                    cdText,
                                    fp,
                                    s2.debuffDurTextSize or 8,
                                    "raidFrames"
                                )
                                cdText:SetTextColor(dtc.r, dtc.g, dtc.b)
                                cdText:ClearAllPoints()
                                cdText:SetPoint(
                                    "CENTER",
                                    iconTex,
                                    "CENTER",
                                    s2.debuffDurTextOffsetX or 0,
                                    s2.debuffDurTextOffsetY or 0
                                )
                            end
                        end
                    end
                    mod.RFC_PreviewAuraBorder(iconTex, iconTex._borderFrame, s2, "debuffBorder")
                    iconTex:Show()
                    -- Re-pack all shown debuffs so slot 1 takes the first position
                    -- and any random slot-2+ debuff shifts right, rather than the
                    -- two overlapping when the pulse returns.
                    PvAuraReanchorFrame(fi, "db")
                    mod._pvActiveAuras[key] = {
                        frameIndex = fi,
                        auraType = "db",
                        slot = 1,
                        expTime = nowTime + dur,
                    }
                end
            end
            pulseInfo.active = true
            pulseInfo.expTime = nowTime + dur
        end

        -- Row-wrap showcase: when wrapping is enabled, fill the player frame
        -- (index 1) up to debuffCap so the full multi-row layout is actually
        -- visible -- the ambient pulse/random spawns only put 1-2 per frame,
        -- which can't demonstrate wrapping. Slots 2+ loop on their own (see the
        -- expiry pass); slot 1 is re-topped here since the pulse skips frame 1.
        if (s2.debuffPerRow or 1) > 1 then
            local cap = s2.debuffCap or 3
            local f1 = PvFrames()[1]
            if f1 and f1._pvDebuffs then
                local changed = false
                for slot = 1, cap do
                    if f1._pvDebuffs[slot] then
                        local key = "1:db:" .. slot
                        local details = mod._pvActiveAuras[key]
                        if not (details and details.expTime > nowTime) then
                            PvAuraApply(1, "db", slot)
                            changed = true
                        end
                    end
                end
                if changed then
                    PvAuraReanchorFrame(1, "db")
                end
            end
        end
    end

    -- Ensure minimum random auras per group for each enabled category.
    -- Party is a single group of 5, so it gets a higher per-group defensive
    -- count (3) to read as a populated showcase; raid keeps 1 per group.
    local defTarget = mod._partyPvActive and 3 or 1
    for set = 1, 4 do
        while wantDef and PvAuraCountInGroup(set, "def") < defTarget do
            local fi = PvAuraPickFrame(set, "def")
            if not fi then
                break
            end
            PvAuraApply(fi, "def", 1)
            PvAuraReanchorFrame(fi, "def")
        end
        -- Random debuffs use slot 2+
        if wantDb and PvAuraCountInGroup(set, "db", 2) < 1 then
            local fi = PvAuraPickFrame(set, "db", 2)
            if fi then
                PvAuraApply(fi, "db", 2)
                PvAuraReanchorFrame(fi, "db")
            end
        end
    end

    -- Assign stacks "2" to exactly one active debuff (slot 2+).
    -- Stays on the same icon until it expires, then the next new one gets it.
    if wantDb and s2.debuffShowStacks then
        -- Check if current stacks target is still alive
        local stackKey = mod._pvActiveAuras._stackKey
        local stackAlive = stackKey
            and mod._pvActiveAuras[stackKey]
            and mod._pvActiveAuras[stackKey].expTime > nowTime
        if not stackAlive then
            -- Clear old stacks text
            if stackKey then
                local oldInfo = mod._pvActiveAuras[stackKey]
                -- oldInfo may have been wiped already
            end
            mod._pvActiveAuras._stackKey = nil
        end
        -- If no current target, assign to the next new debuff that appears
        -- (handled in PvAuraApply via _pvNeedStacks flag)
        if not mod._pvActiveAuras._stackKey then
            -- Find any active slot 2+ debuff to assign stacks to
            for key, details in pairs(mod._pvActiveAuras) do
                if
                    key ~= "_stackKey"
                    and details.auraType == "db"
                    and details.slot >= 2
                    and details.expTime > nowTime
                then
                    mod._pvActiveAuras._stackKey = key
                    local frame = PvFrames()[details.frameIndex]
                    local ic = frame and frame._pvDebuffs and frame._pvDebuffs[details.slot]
                    if ic and ic._count then
                        local stc = s2.debuffStacksTextColor or { r = 1, g = 1, b = 1 }
                        local fp = (CludesUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
                        CludesUI.ApplyIconTextFont(ic._count, fp, s2.debuffStacksTextSize or 8, "raidFrames")
                        ic._count:SetTextColor(stc.r, stc.g, stc.b)
                        ic._count:ClearAllPoints()
                        ic._count:SetPoint(
                            "BOTTOMRIGHT",
                            ic,
                            "BOTTOMRIGHT",
                            1 + (s2.debuffStacksOffsetX or 0),
                            -1 + (s2.debuffStacksOffsetY or 0)
                        )
                        ic._count:SetText("2")
                    end
                    break
                end
            end
        end
    end
end

local function StartPvAuraTicker()
    if not pvAuraTicker then
        -- Seed initial auras
        PvAuraTick()
        pvAuraTicker = C_Timer.NewTicker(0.5, PvAuraTick)
    end
end

local function StopPvAuraTicker()
    if pvAuraTicker then
        pvAuraTicker:Cancel()
        pvAuraTicker = nil
    end
    wipe(mod._pvActiveAuras)
    -- Hide all preview aura icons, reset cooldowns, unregister dur texts
    for _, frame in ipairs(PvFrames()) do
        if frame._pvDebuffs then
            for _, ic in ipairs(frame._pvDebuffs) do
                ic:Hide()
                if ic._cooldown then
                    ic._cooldown:Clear()
                end
            end
        end
        if frame._pvDefs then
            for _, ic in ipairs(frame._pvDefs) do
                ic:Hide()
                if ic._cooldown then
                    ic._cooldown:Clear()
                end
            end
        end
    end
end

Inner.PvActive, Inner.PvAuraReanchorFrame, Inner.PvFrames = PvActive, PvAuraReanchorFrame, PvFrames
Inner.PvSettings, Inner.StartPvAuraTicker = PvSettings, StartPvAuraTicker
Inner.StopPvAuraTicker = StopPvAuraTicker
Inner.broken = false
