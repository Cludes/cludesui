if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-- CUI_Nameplates_AuraContainers.lua
-- 12.1 aura containers for nameplates. Three engine-driven groups per
-- plate (player debuffs, enemy important buffs, crowd control), rendered
-- through a PRE-CREATED pool of container bundles: plates spawn lazily in
-- combat, but containers can only be created out of combat, so bundles are
-- built at login and attached/detached as plates come and go.
--
-- Importance: Blizzard's per-plate debuffList/buffList are taint-locked in
-- 12.1 (unreadable), but their build rule (Blizzard_NamePlateAuras) is
-- fetch HARMFUL|INCLUDE_NAME_PLATE_ONLY then keep nameplateShowPersonal
-- auras -- reproduced on the debuff group as the same fetch tokens plus a
-- { nameplateShowPersonal = true } candidate filter. "Show All Debuffs"
-- clears the candidate filter live and switches the sort to Default.
--
-- V1 deferred (documented): purge/dispel glow on buffs, pandemic glow
-- (engine has no duration-driven texture alpha -- wishlist), cast-lockout
-- offset interplay with the CC row (lockout renders independently), target
-- arrows relative to aura rows, per-slot Raise Strata on containers.

local _, mod = ...
local CludesUI = _G.CludesUI
local Pix = CludesUI.PP

mod.NPC_OwnsAuras = true
-- Born in this module's main chunk, so the aura containers it builds bill this
-- module (AuraKit's shared build scheduler).
local AKWorker = CludesUI.AuraKit.NewBuildWorker()

local AK
-- Warm-cache size only, no longer a hard ceiling: container creation is
-- combat-legal since 68914 (/cuit3 field PASS), so pool exhaustion queues
-- an on-demand bundle per waiting plate instead of degrading to no-auras.
-- 16 covers 5-man content with margin; raids grow within a few worker
-- frames on first exposure and the grown bundles stay pooled.
local POOL_SIZE = 16
-- Instanced-content pre-warm target: M+ trash pulls are the heaviest
-- sustained plate counts in the game (raid add waves close behind), so
-- zoning into a dungeon or raid tops the pool up to this in advance --
-- the growth ramp runs while zoning instead of on the first big pull.
local POOL_TARGET_INSTANCE = 25
local queuedBundles = 0 -- total trios ever queued (login + growth + pre-warm)
local QueueBundleBuild -- forward-declared: the attach path below grows the pool on demand

local pool = {} -- free bundles (stack)
local isActive = {} -- [plate] = bundle
local KINDS = { "debuffs", "buffs", "cc" }

-- Layout generation: bumped whenever the geometry fingerprint changes. Containers stamp
-- the generation (plus the slot they were laid out for) when their engine layout config
-- is driven; a matching stamp means the bundle-local layout state is already correct,
-- so plate attach/re-anchor passes skip the engine layout setters (each one is a dirty
-- mark that costs real engine work) and only re-run the plate-dependent SetPoint.
local geoGen = 1
local lastTargetPlate

local FP_JOIN = {}
local function FP(...)
    local num = select("#", ...)
    for i = 1, num do
        local val = select(i, ...)
        if type(val) == "number" then
            FP_JOIN[i] = string.format("%.2f", val)
        else
            FP_JOIN[i] = tostring(val)
        end
    end
    for i = num + 1, #FP_JOIN do
        FP_JOIN[i] = nil
    end
    return table.concat(FP_JOIN, "|")
end

local function PVal(auraKey)
    local p = mod.NP_GetProfile and mod.NP_GetProfile()
    if p and p[auraKey] ~= nil then
        return p[auraKey]
    end
    local skinData = mod.NP_GetDefaults and mod.NP_GetDefaults()
    return skinData and skinData[auraKey]
end

------------------------------------------------------------------------------
-- Styles. Duration text = our formatter-driven FontString styled like the
-- legacy cooldown countdown text; stacks mirror the legacy count strings.
-- Cropped icons are shorter than wide (legacy crop system): height and
-- vertical texcoords derive from the shared crop math.
------------------------------------------------------------------------------

local function CropCoords(isCropped, zoom)
    -- Horizontal zoom 0.08 (Blizzard Style passes 0: the stock item draws the
    -- whole icon under its rounded mask, same as PAB and the unit frames).
    local z = zoom or 0.08
    if isCropped then
        -- Vertical span scaled to the cropped aspect so the artwork never
        -- squishes (same math as ns.SetAuraIconCrop).
        -- `cropped` carries the height factor from GetAuraCrop (Adjust Crop
        -- slider); plain true from a legacy caller falls back to the classic
        -- 0.80, which reproduces the old fixed coords exactly (0.164/0.836).
        local factor = (type(isCropped) == "number") and isCropped or 0.80
        local vSpan = (1 - 2 * z) * factor
        local v0 = 0.5 - vSpan / 2
        return { z, 1 - z, v0, 1 - v0 }
    end
    return { z, 1 - z, z, 1 - z }
end

local function NPSize(kindName)
    if kindName == "debuffs" then
        return (mod.GetDebuffIconSize and mod.GetDebuffIconSize()) or 26
    end
    if kindName == "buffs" then
        return (mod.GetBuffIconSize and mod.GetBuffIconSize()) or 24
    end
    return (mod.GetCCIconSize and mod.GetCCIconSize()) or 24
end

local function NPHeight(kindName, px)
    local isCropped = mod.GetAuraCrop and mod.GetAuraCrop(kindName == "cc" and "ccs" or kindName)
    if isCropped and mod.GetAuraCropHeight then
        -- Second return is GetAuraCrop's value itself (the height factor,
        -- truthy) so CropCoords can derive matching texcoords; truth-testing
        -- callers behave exactly as with the old literal `true`.
        return mod.GetAuraCropHeight(isCropped, px), isCropped
    end
    return px, false
end

-- Legacy settings resolution for aura text -- the EXACT fallback chains
-- ApplyAppearance uses (per-kind key -> shared legacy aura* key -> defaults),
-- so 12.0 and 12.1 render identical text for any profile state.
-- kindKey = "debuff" | "buff" | "cc".
local function ProfOnly(auraKey)
    local prof = mod.NP_GetProfile and mod.NP_GetProfile()
    return prof and prof[auraKey]
end
local function Dflt(auraKey)
    local skinData = mod.NP_GetDefaults and mod.NP_GetDefaults()
    return skinData and skinData[auraKey]
end
local function AuraDurCfg(kindKey)
    return {
        size = ProfOnly(kindKey .. "DurationTextSize") or ProfOnly("auraDurationTextSize") or Dflt(
            "auraDurationTextSize"
        ) or 11,
        x = ProfOnly(kindKey .. "DurationTextX") or ProfOnly("auraDurationTextX") or Dflt(
            "auraDurationTextX"
        ) or 0,
        y = ProfOnly(kindKey .. "DurationTextY") or ProfOnly("auraDurationTextY") or Dflt(
            "auraDurationTextY"
        ) or 0,
        color = ProfOnly(kindKey .. "DurationTextColor") or ProfOnly("auraDurationTextColor") or Dflt(
            "auraDurationTextColor"
        ) or { r = 1, g = 1, b = 1 },
        pos = ProfOnly(kindKey .. "TimerPosition") or ProfOnly("auraTextPosition") or Dflt(
            kindKey .. "TimerPosition"
        ) or "topleft",
    }
end
local function StackCfg()
    return {
        size = PVal("auraStackTextSize") or 11,
        color = PVal("auraStackTextColor") or { r = 1, g = 1, b = 1 },
        x = PVal("auraStackTextX") or 0,
        y = PVal("auraStackTextY") or 0,
        pos = PVal("auraStackTextPosition") or "bottomright",
    }
end

-- Position -> corner/nudge/justify: a baked edge nudge per corner, the user's
-- X/Y on top.
local TEXT_POS = {
    center = { point = "CENTER", nx = 0, ny = 0, justify = "CENTER" },
    topright = { point = "TOPRIGHT", nx = 3, ny = 4, justify = "RIGHT" },
    bottomleft = { point = "BOTTOMLEFT", nx = -3, ny = -4, justify = "LEFT" },
    bottomright = { point = "BOTTOMRIGHT", nx = 3, ny = -4, justify = "RIGHT" },
    topleft = { point = "TOPLEFT", nx = -3, ny = 4, justify = "LEFT" },
}

-- Text pass shared by the three styles; anchors/sizes carried per style.
local function ApplyNPText(btnFrame, skinData, look)
    if btnFrame.SetMouseMotionEnabled then
        local motion = not look.noTooltips
        if skinData.npMotion ~= motion then
            skinData.npMotion = motion
            btnFrame:SetMouseMotionEnabled(motion)
        end
    end
    local filePath = (CludesUI.GetFontPath("nameplates")) or "Fonts\\FRIZQT__.TTF"
    if skinData.duration then
        local fontKey = filePath .. "|" .. (look.durSize or 11)
        if skinData.npDurFont ~= fontKey then
            skinData.npDurFont = fontKey
            CludesUI.ApplyIconTextFont(skinData.duration, filePath, look.durSize or 11, "nameplates")
        end
        local color = look.durColor
        skinData.duration:SetTextColor(color and color.r or 1, color and color.g or 1, color and color.b or 1)
        local m = TEXT_POS[look.durPos] or TEXT_POS.topleft
        -- Anchor change-guarded (stamp AFTER the calls): SetPoint with the
        -- button as the relative frame is policed by the 12.1 button access
        -- restriction while auras are secret; unchanged anchors must make
        -- zero button-involving calls so restyles stay live in-instance.
        local aKey = m.point .. "|" .. (m.nx + (look.durOffX or 0)) .. "|" .. (m.ny + (look.durOffY or 0))
        if skinData.npDurAnchor ~= aKey then
            skinData.duration:ClearAllPoints()
            skinData.duration:SetPoint(
                m.point,
                btnFrame,
                m.point,
                m.nx + (look.durOffX or 0),
                m.ny + (look.durOffY or 0)
            )
            skinData.npDurAnchor = aKey
        end
        skinData.duration:SetJustifyH(m.justify)
        skinData.duration:SetShown(not look.hideDurationText)
    end
    if skinData.stack then
        skinData.stack:SetShown(look.showStacks ~= false)
        local fontKey = filePath .. "|" .. (look.stackSize or 11)
        if skinData.npStackFont ~= fontKey then
            skinData.npStackFont = fontKey
            CludesUI.ApplyIconTextFont(skinData.stack, filePath, look.stackSize or 11, "nameplates")
        end
        local sc = look.stackColor
        skinData.stack:SetTextColor(sc and sc.r or 1, sc and sc.g or 1, sc and sc.b or 1)
        local m = TEXT_POS[look.stackPos] or TEXT_POS.bottomright
        local sKey = m.point
            .. "|"
            .. (m.nx + (look.stackOffX or 0))
            .. "|"
            .. (m.ny + (look.stackOffY or 0))
        if skinData.npStackAnchor ~= sKey then
            skinData.stack:ClearAllPoints()
            skinData.stack:SetPoint(
                m.point,
                btnFrame,
                m.point,
                m.nx + (look.stackOffX or 0),
                m.ny + (look.stackOffY or 0)
            )
            skinData.npStackAnchor = sKey
        end
        skinData.stack:SetJustifyH(m.justify)
    end
end

-- Buffs pass: shared text styling + the purge glow. Dispellability of a SPECIFIC shown buff
-- is unreadable in restricted content -- the engine aura border that used to signal it is a
-- button call the client denies while auras are secret, so in instanced PvP a per-aura glow
-- never lit. The GROUP answers the question instead: the row renders as two engine groups
-- (see BuffFilterGlow/BuffFilterPlain) and this glow style belongs only to the dispellable
-- group, so every buff carrying it is purgeable by construction and no per-aura signal is
-- needed under any filter mode. Style and color come from the Dispel Glow options.

-- Engine tokens, declared up here because PurgeGlowActive reads DISPELLABLE
-- (a file-scope local is invisible to functions defined above it).
-- DISPELLABLE = "dispellable regardless of whether the player's raid can
-- dispel them" (Blizzard's own comment); the sibling RAID_PLAYER_DISPELLABLE
-- comment names helpful enrages on enemies as dispellable, so enrages are in.
local DISPELLABLE = AuraUtil and AuraUtil.AuraFilters and AuraUtil.AuraFilters.Dispellable
-- "helpful auras that show on enemy nameplates even if non-stealable" -- the
-- purpose-built enemy-buff curation token (source-verified 2026-08-16).
local IMPORTANT = AuraUtil and AuraUtil.AuraFilters and AuraUtil.AuraFilters.Important
-- "Dispellable By Me" (npEnemyBuffDispelByMe, retail, nil = off): Important
-- and Only Dispellable narrow "dispellable" to the group's own dispels.
local RAID_DISPELLABLE = AuraUtil and AuraUtil.AuraFilters and AuraUtil.AuraFilters.RaidPlayerDispellable

-- Effective glow state: the Dispel Glow setting AND the player's offensive
-- dispel capability (the option promises "you can dispel this", and the
-- engine's class-independent DISPELLABLE token cannot answer that alone).
-- The glow stays INDEPENDENT of the Enemy Buff Filter: it styles the
-- dispellable GROUP, so under any filter mode only dispellable buffs carry
-- it. A character with no offensive dispel gets no glow; without the
-- DISPELLABLE token nothing can be claimed dispellable by anyone.
local function PurgeGlowActive()
    if not (mod.GetDispelGlow and mod.GetDispelGlow()) then
        return false
    end
    if not DISPELLABLE then
        return false
    end
    local magic, enrage = false, false
    if mod.GetOffensiveDispelTypes then
        magic, enrage = mod.GetOffensiveDispelTypes()
    end
    return magic or enrage
end

-- Buff row capability split (one table = one file-scope local; GlowSpec and
-- Apply are filled in near AddBundleBuffs, below the locals they read).
-- DISPELLABLE admits Magic buffs AND enrages, and the player rarely removes
-- both, so the glow group is cut into exact complements: "np" carries Magic
-- (includeDispelTypes), "np2" carries everything else -- which on an enemy
-- buff means an enrage (no dispelName: include rejects it, exclude keeps
-- it). Nothing is hidden by the split; only glow and color follow capability.
local NPB = {
    MAGIC = { includeDispelTypes = { Magic = true } },
    NONMAGIC = { excludeDispelTypes = { Magic = true } },
}

-- The split costs an extra engine group per plate, so take it only when the
-- halves must differ: one dispel type known and not the other, or both known
-- with per-type colors on (never for Blizzard Pandemic Border, which takes no
-- color). AND ONLY UNRESTRICTED: candidate filters read
-- auraData.dispelName, and enemy aura data is REDACTED in restricted content
-- (the documented isStealable incident above BuffCand) -- there the
-- include-Magic candidate matches nothing and every buff would fall into the
-- non-Magic group. Restricted content runs the single blanket-glow group
-- instead (exactly the unsplit behavior); the boot's PEW lane reloads when
-- restriction flips across a zone edge.
function NPB.Split()
    if not PurgeGlowActive() then
        return false
    end
    if AK and AK.AurasRestricted and AK.AurasRestricted() then
        return false
    end
    local magic, enrage = mod.GetOffensiveDispelTypes()
    if magic ~= enrage then
        return true
    end
    if mod.GetDispelGlowStyle() == CludesUI.Glows.PANDEMIC_BORDER then
        return false
    end
    return (mod.GetDispelGlowUseTypeColor and mod.GetDispelGlowUseTypeColor()) or false
end

-- Glow state and dispel type for glow group idx (1 = Magic, or the whole row
-- while unsplit; 2 = non-Magic). The type passes on unconditionally --
-- GetDispelGlowColor ignores it unless per-type colors are on.
function NPB.GroupGlow(position)
    if not PurgeGlowActive() then
        return false, nil
    end
    if not NPB.Split() then
        return position ~= 2, nil
    end
    local magic, enrage = mod.GetOffensiveDispelTypes()
    if position == 2 then
        return enrage == true, "enrage"
    end
    return magic == true, "magic"
end

-- The glow host of an engine aura button in d[key], made on first use (in the
-- button's creation window, or by a restyle out of restriction): a child of
-- the engine button (cross-tree anchoring TO engine buttons is disallowed --
-- the dependent would inherit their forbidden aspects) covering it. Just above
-- the border, below the duration/stack text: the text carrier sits one level
-- over the border host, so slot in at carrier-1 (equal level with the border
-- host still draws the glow on top of the border, created later). Bound to
-- the button (CludesUI.Glows.BindEngineHost): the button itself plays the
-- glow's animations while it shows an aura and stops them whenever it has
-- none, so the hosts on hidden pooled buttons cost nothing. No prewarm:
-- StartSpecGlow makes the regions of the style it draws, so a default host
-- holds just the static border, and a later style makes its own. Made only on
-- buttons that can ever show an aura (NPGlowable).
local function NPGlowHost(btnFrame, skinData, auraKey)
    local owner = skinData[auraKey]
    if owner then
        return owner
    end
    owner = CreateFrame("Frame", nil, btnFrame)
    owner:SetAllPoints(btnFrame)
    if skinData.stackCarrier then
        owner:SetFrameLevel(skinData.stackCarrier:GetFrameLevel() - 1)
    else
        owner:SetFrameLevel(btnFrame:GetFrameLevel() + 1)
    end
    owner:EnableMouse(false)
    skinData[auraKey] = owner
    -- NPB.bound: some button plays a glow itself, so a pooled bundle's
    -- buttons are worth releasing (NPB.ReleaseGlowButtons).
    if CludesUI.Glows.BindEngineHost(owner, btnFrame, skinData) then
        NPB.bound = true
    end
    return owner
end

-- Whether a button gets a glow at all: only the buttons that can ever show an
-- aura (AuraKit.ButtonCanShow). Each group builds a 10-button batch but shows
-- at most its cap (5 debuffs, 1 for a one-icon group), so most pooled buttons
-- never show; skipping their glow setup keeps it out of the login build. The
-- others are dressed again when their group's cap grows (AuraKit re-runs the
-- style on them), the path an unbound host (a client whose buttons cannot run
-- animations themselves) has always taken.
local function NPGlowable(btnFrame)
    return CludesUI.AuraKit.ButtonCanShow(btnFrame)
end

-- Draws spec on the glow host, sized to the icon (the height follows cropped
-- icons); unchanged, StartSpecGlow returns at once. Callers pass only glowable
-- buttons; a bound host's button decides when the animations play.
local function NPStartGlow(owner, specInfo, look)
    owner:SetAlpha(1)
    local sz = look.width or 24
    CludesUI.Glows.StartSpecGlow(owner, specInfo, sz, look.height or sz, "engine")
end

-- Dispel Glow on the buff row: every buff in the glow group is dispellable (the
-- group filter says so), so the glow rides the button's own visibility -- no
-- readback of per-aura state. purgeSpec is the dispel glow's full spec
-- (ns.GetDispelGlowSpec), built once per style pass. The static Blizzard
-- Border and Blizzard Pandemic Border render through the same call.
local function ApplyNPBuffExtra(btnFrame, skinData, look)
    ApplyNPText(btnFrame, skinData, look)
    if look.purgeGlow and look.purgeSpec and NPGlowable(btnFrame) then
        NPStartGlow(NPGlowHost(btnFrame, skinData, "npGlowHost"), look.purgeSpec, look)
    elseif skinData.npGlowHost then
        local owner = skinData.npGlowHost
        if owner._cuiGlowActive then
            CludesUI.Glows.StopGlow(owner)
        end
        owner:SetAlpha(0)
    end
end

-- Pandemic Glow on debuff icons. The glow host is a PANDEMIC REGION of the
-- engine button: the client shows it only while the aura is in its pandemic
-- window, also under restriction, and its shown state is secret -- nothing
-- here reads it. Its animations run while the button shows an aura (the host
-- binding above) and are seen only inside the window. Off, the region is
-- cleared, so the button no longer checks the window. Blizzard's aura code
-- runs in its own environment (no global mixin to test), so the button's own
-- method is the one capability check.
local function ApplyNPDebuffExtra(btnFrame, skinData, look)
    ApplyNPText(btnFrame, skinData, look)
    local owner = skinData.npPanHost
    if look.pandemicGlow and look.pandemicSpec and btnFrame.AddPandemicRegion and NPGlowable(btnFrame) then
        owner = NPGlowHost(btnFrame, skinData, "npPanHost")
        if not skinData.npPanRegion then
            btnFrame:AddPandemicRegion(owner)
            skinData.npPanRegion = true
        end
        NPStartGlow(owner, look.pandemicSpec, look)
    elseif owner then
        if skinData.npPanRegion then
            btnFrame:ClearPandemicRegions()
            skinData.npPanRegion = nil
        end
        if owner._cuiGlowActive then
            CludesUI.Glows.StopGlow(owner)
        end
        owner:SetAlpha(0)
    end
end

-- Custom Border on Aura Icons (auraIconCustomBorder, Border = Custom): true while the
-- aura icons wear the plate's custom border. The toggle is read first, so off it costs
-- one field read.
local function NPIconCustomBorderOn()
    return PVal("auraIconCustomBorder") == true and mod.IsCustomBorderEnabled()
end

-- The plate's custom border as an AuraKit border table. Solid sets no texture key, so
-- it rides the plain PP lane at its size or exact px; a textured style rides the
-- eight-slice lane with the nameplate registry offsets (addonKey), its step (sizeKey)
-- and exact px. Show Behind is not carried: behind the opaque icon it would vanish.
local function NPCustomIconBorder()
    local texture = PVal("customBorderTexture")
    local sz = PVal("customBorderSize") or 1
    local colour = PVal("customBorderColor")
    local t = {
        colour.r,
        colour.g,
        colour.b,
        PVal("customBorderAlpha") or 1,
        size = sz,
        edgePx = CludesUI.BorderPx(PVal("customBorderSizePx"), sz, texture),
    }
    if texture and texture ~= "" and texture ~= "solid" then
        t.texture, t.sizeKey, t.addonKey = texture, sz, "nameplates"
        t.offsetX, t.offsetY = PVal("customBorderOffset"), PVal("customBorderOffsetY")
        t.shiftX, t.shiftY = PVal("customBorderShiftX"), PVal("customBorderShiftY")
    end
    return t
end

local function BuildNPStyle(kindName, variant)
    local px = NPSize(kindName)
    local height, isCropped = NPHeight(kindName, px)
    -- User text settings, resolved through the legacy fallback chains, so
    -- every Duration/Stacks option (size, color, position, X/Y) renders
    -- exactly like the 12.0 aura pools.
    local kindKey = (kindName == "debuffs" and "debuff") or (kindName == "buffs" and "buff") or "cc"
    local duration = AuraDurCfg(kindKey)
    local stacks = StackCfg()
    -- Stock styles: the whole icon (zoom 0), no CUI border (GetIconBorderEnabled
    -- is false for every kind under them). Blizzard Style: the stock nameplate
    -- aura item -- the rounded mask with the ring overlay (AuraKit
    -- blizzRoundArt). Classic WoW UI: square icons, buffs borderless, debuffs
    -- and crowd control on the engine-stamped stock dispel-type border (AuraKit
    -- blizzBorder). Text, stacks, sizes and the dispel glow all stay the user's.
    local blizz = mod.NP_Blizz()
    local classic = blizz and mod.NP_Classic()
    local harmfulClassic = (classic and kindName ~= "buffs") or nil
    local look = {
        width = px,
        height = height,
        texCoord = CropCoords(isCropped, blizz and 0 or nil),
        -- Off: the plain 1px black edge (plain lane); a per-kind Hide
        -- Border still wins over the custom border.
        border = (not mod.GetIconBorderEnabled or mod.GetIconBorderEnabled(kindName))
                and (NPIconCustomBorderOn() and NPCustomIconBorder() or { 0, 0, 0, 1, size = 1 })
            or false,
        blizzRoundArt = (blizz and not classic) or nil,
        -- The WoW Forever variant keeps that client's own ring (AuraKit
        -- paints the retail one through CludesUI.StockAtlas otherwise).
        blizzRoundNative = mod.NP_Forever() or nil,
        dispelBorder = harmfulClassic,
        blizzBorder = harmfulClassic,
        cooldownReverse = true,
        noDefaultFonts = true,
        noTooltips = PVal("showAuraTooltips") ~= true,
        applyExtra = ApplyNPText,
        durSize = duration.size,
        durColor = duration.color,
        durPos = duration.pos,
        durOffX = duration.x,
        durOffY = duration.y,
        -- "None" is the duration text's show/hide switch (legacy semantics:
        -- position dropdown "None" = hidden).
        hideDurationText = (duration.pos == "none"),
        -- CC icons never render stacks (legacy parity); the shared Aura
        -- Stacks position "None" hides them everywhere else.
        showStacks = (kindName ~= "cc") and (stacks.pos ~= "none"),
        stackSize = stacks.size,
        stackColor = stacks.color,
        stackPos = stacks.pos,
        stackOffX = stacks.x,
        stackOffY = stacks.y,
    }
    -- variant: nil/1 = the dispellable glow group ("np" -- the Magic half
    -- while split), 2 = the non-Magic half ("np2", enrages), "plain" = the
    -- npnb remainder: identical text styling, NEVER the glow. Per-aura
    -- dispel type is unreadable under 12.1 secrecy, so the type is a
    -- property of the GROUP and resolves once, here, at style-build time.
    if kindName == "buffs" and variant ~= "plain" then
        local glow, dispelType = NPB.GroupGlow(variant == 2 and 2 or 1)
        look.purgeGlow = glow
        look.purgeSpec = mod.GetDispelGlowSpec and mod.GetDispelGlowSpec(dispelType) or nil
        look.applyExtra = ApplyNPBuffExtra
    elseif kindName == "debuffs" then
        -- Your debuffs only: the pandemic window is the time a recast keeps.
        look.pandemicGlow = mod.GetPandemicGlow()
        look.pandemicSpec = look.pandemicGlow and mod.GetPandemicGlowSpec() or nil
        look.applyExtra = ApplyNPDebuffExtra
    end
    return look
end

------------------------------------------------------------------------------
-- Bundle pool
------------------------------------------------------------------------------

local SORT_IMPORTANT, SORT_DEFAULT, SORT_DIR

-------------------------------------------------------------------------------
-- Slot filter model (Tracked Auras popup). Filter COMPOSITION is fixed
-- per aura CONTENT KIND -- debuffs = Default, dcc ("Debuffs + CC") =
-- CC + Default, cc = CC -- with no user-facing category selection. The
-- stored knobs at p.npAuraFilters: debuffs.all (the debuffs slot's Show All Debuffs
-- toggle; dcc/cc have no such mode), the debuff-side spell lists (exclude/include --
-- shared by the debuffs and dcc kinds, i.e. the debuff container), and the cc slot's
-- own lists (ccExclude/ ccInclude). The debuff container renders the dcc composition
-- when p.debuffIncludeCC is set (kind resolution is a selector; both slots can
-- coexist). debuffs.all seeds ONCE from the legacy showAllDebuffs key, which is left
-- untouched after seeding.
-------------------------------------------------------------------------------
-- Category vocabulary is deliberately just Important + Crowd Control;
-- explicit per-spell tracking goes through the include list instead.
-- Stored flags from retired categories (boss/role/raid/raidcombat/
-- dispel) persist harmlessly in old profiles -- nothing reads them.
local NPF_ORDER = { "cc" } -- token-category ownership order (DM parity)
local NPF_TOKENS = {
    cc = { "HARMFUL", "CROWD_CONTROL" }, -- any caster, matching the cc feed
}
local NPF_NEG = { cc = "!CROWD_CONTROL" }
-- Boolean categories: Important = nameplateShowPersonal (nameplate-native
-- importance -- the pre-filter default display, NOT the raid-frame
-- isPriorityAura list; user-confirmed zero-drift mapping).
local NPF_BOOL = { priority = "nameplateShowPersonal" }

-- The internal per-kind composition (see the model comment above).
local NPF_VIEW = {
    debuffs = { all = false, f = { priority = true } },
    dcc = { all = false, f = { cc = true, priority = true } },
    cc = { all = false, f = { cc = true } },
}

function mod.NPF_Root()
    local p = mod.NP_GetProfile and mod.NP_GetProfile()
    if not p then
        return nil
    end
    local t = p.npAuraFilters
    if not t then
        t = { debuffs = { all = PVal("showAllDebuffs") == true }, fv3 = true }
        p.npAuraFilters = t
    elseif not t.fv3 then
        -- One-shot (per profile, first touch): category selections moved
        -- from stored per-kind sets to the internal composition above --
        -- clear them, keep Show All and both spell lists (existing lists
        -- become the debuff side; the cc side starts empty).
        t.debuffs = { all = (t.debuffs and t.debuffs.all == true) or false }
        t.cc = nil
        t.dcc = nil
        t.fv2 = nil
        t.fv3 = true
    end
    return t
end

-- Read-only per-kind VIEW (static tables, no per-call allocation):
-- callers treat the result as immutable and never retain it across
-- frames. Show All writes go through ns.NPF_Root().debuffs.all -- only
-- the debuffs kind has that mode, so the view pins all = false for
-- dcc/cc.
function mod.NPF_Config(kindName)
    local t = mod.NPF_Root()
    local val = t and NPF_VIEW[kindName]
    if not val then
        return nil
    end
    val.all = (kindName == "debuffs") and (t.debuffs and t.debuffs.all == true) or false
    return val
end

-- Record synthesis for one kind config: token categories own overlaps in NPF_ORDER
-- order (each negates the ENABLED tokens above it -- negating disabled ones would eat
-- their auras); boolean categories negate every enabled token. Show All returns no
-- records: the plain "np" group is the whole display then. Booleans can never be
-- negated (engine positive-only history); a boolean x boolean overlap double-renders
-- -- accepted, DM precedent.
local function NPF_Records(conf)
    local recs = {}
    if not conf or conf.all then
        return recs
    end
    local frame = conf.f or {}
    for i = 1, #NPF_ORDER do
        local category = NPF_ORDER[i]
        if frame[category] then
            local toks = {}
            for k = 1, #NPF_TOKENS[category] do
                toks[#toks + 1] = NPF_TOKENS[category][k]
            end
            for jdx = 1, i - 1 do
                local hc = NPF_ORDER[jdx]
                if frame[hc] then
                    toks[#toks + 1] = NPF_NEG[hc]
                end
            end
            recs[#recs + 1] = { cat = category, tokens = toks }
        end
    end
    for category, boolField in pairs(NPF_BOOL) do
        if frame[category] then
            local toks = { "HARMFUL", "PLAYER", "INCLUDE_NAME_PLATE_ONLY", "!CROWD_CONTROL" }
            for i = 2, #NPF_ORDER do
                local tc = NPF_ORDER[i]
                if frame[tc] then
                    toks[#toks + 1] = NPF_NEG[tc]
                end
            end
            recs[#recs + 1] = { cat = category, tokens = toks, cand = { [boolField] = true } }
        end
    end
    return recs
end

-- Stable per-record group key: category + a hash of the negation-relevant
-- enabled set. A filter edit that changes the chain declares the NEW
-- variant and parks the old one at 0 (group filter strings are fixed).
local function NPF_GKey(category, conf)
    local frame = conf.f or {}
    return "npf:" .. category .. "|" .. (frame.cc and 1 or 0)
end

-- Filter-state fingerprint for the reload cfg pass. The per-kind compositions are
-- internal constants now, so the ONLY inputs are the debuffs slot's Show All flag and
-- the four spell lists (list edits must re-drive every group's candidates).
function mod.NPF_FP()
    local t = mod.NPF_Root()
    local parts = {}
    parts[1] = (t and t.debuffs and t.debuffs.all == true) and "A" or "-"
    local function ListPart(prefixText, entries)
        if entries and next(entries) ~= nil then
            local o = {}
            for ident, val in pairs(entries) do
                -- Disabled entries prefix "-" (all strings: mixed-type sort errors)
                o[#o + 1] = (val and "" or "-") .. ident
            end
            table.sort(o)
            parts[#parts + 1] = prefixText .. table.concat(o, ",")
        end
    end
    ListPart("x", mod.NPF_Exclude("debuff"))
    ListPart("n", mod.NPF_Include("debuff"))
    ListPart("cx", mod.NPF_Exclude("cc"))
    ListPart("cn", mod.NPF_Include("cc"))
    -- Any-caster opt-outs are re-drive inputs too: they move ids between
    -- the npinc and npincmine groups (a memo missing an input is a
    -- correctness bug -- toggling MINE must not no-op the reload).
    ListPart("na", mod.NPF_IncludeAny("debuff"))
    ListPart("cna", mod.NPF_IncludeAny("cc"))
    return table.concat(parts, ";")
end

-- The debuff container renders the dcc config when the combined
-- "Debuffs + CC" element is assigned (p.debuffIncludeCC), else debuffs.
local function NPF_DebuffKind()
    return PVal("debuffIncludeCC") and "dcc" or "debuffs"
end

local function DebuffSort()
    local c = mod.NPF_Config(NPF_DebuffKind())
    local all = c and c.all
    if all == nil then
        all = PVal("showAllDebuffs")
    end -- pre-seed fallback
    if all then
        return SORT_DEFAULT
    end
    return SORT_IMPORTANT
end

-- Debuff importance: Blizzard's 12.1 nameplate rule (Blizzard_NamePlateAuras
-- AddAura) is fetch HARMFUL|INCLUDE_NAME_PLATE_ONLY, then keep only auras
-- flagged nameplateShowPersonal -- that flag IS the "useful debuff" gate that
-- fed the legacy debuffList. INCLUDE_NAME_PLATE_ONLY alone is INCLUSIVE
-- (adds nameplate-only auras to candidacy, does not restrict); the candidate
-- boolean does the narrowing and toggles live. "Show All Debuffs" clears it
-- (empty table, never nil: the setter must REPLACE the stored filter).
-- Nameplate debuff blacklists (Tracked Auras popup, EXCLUDED column):
-- one list per SIDE -- the debuff container's (shared by the debuffs
-- and dcc kinds, so a slot flipping between Debuffs and Debuffs + CC
-- keeps its exclusions) and the cc slot's own. spellID excludes are
-- identity-legal on hostile units (harmful-on-attackable passes the
-- gate), so these are real engine filters, not Lua scans.
function mod.NPF_Exclude(edgeSide)
    local t = mod.NPF_Root()
    if not t then
        return nil
    end
    local auraKey = (edgeSide == "cc") and "ccExclude" or "exclude"
    if not t[auraKey] then
        t[auraKey] = {}
    end
    return t[auraKey]
end

-- Include lists (Tracked Auras popup, INCLUDED column): same tri-state
-- shape and side split as the exclude lists (true = active, false =
-- kept but disabled, nil = deleted). Included spells render through
-- their side's own groups ("npinc" any-caster, "npincmine" own-cast for
-- entries flagged Only My Casts; NPF_ApplyContainer) and are excluded from
-- every other group's candidates on that container, so a spell that also matches the
-- slot's composition (or Show All) can never double-render.
function mod.NPF_Include(edgeSide)
    local t = mod.NPF_Root()
    if not t then
        return nil
    end
    local auraKey = (edgeSide == "cc") and "ccInclude" or "include"
    if not t[auraKey] then
        t[auraKey] = {}
    end
    return t[auraKey]
end

-- Any-caster OPT-OUTS for include entries (default is Only My Casts): a
-- SIBLING map keyed by spell id, not a fourth tri-state value -- every
-- `v == true` reader of the include list stays valid, and the flag
-- survives disable/re-enable cycles.
function mod.NPF_IncludeAny(edgeSide)
    local t = mod.NPF_Root()
    if not t then
        return nil
    end
    local auraKey = (edgeSide == "cc") and "ccIncludeAnyCaster" or "includeAnyCaster"
    if not t[auraKey] then
        t[auraKey] = {}
    end
    return t[auraKey]
end

-- Debuffs the player can stack MANY copies of on one target under one spell
-- id (Blood Plague from weapon copies / guardians): the debuff container shows
-- each of them at most ONCE. The engine has no dedup primitive and Lua cannot
-- see auras under restriction, so each id gets its own single-frame group
-- (includeSpellIDs = that id, maxFrameCount 1: the engine keeps the top sorted
-- candidate) and is excluded from every other debuff-side group. Hardcoded
-- exception list, PLAYER-cast only, debuff container only.
local NPF_ONCE_DEBUFFS = {
    [55078] = true, -- Blood Plague
}

-- WoW Forever: Sunder Armor is one debuff per target that every warrior's
-- casts stack onto, so it renders from any caster. Each rank is its own id.
local NPF_SUNDER_IDS = {
    [7386] = true,
    [7405] = true,
    [8380] = true,
    [11596] = true,
    [11597] = true,
}
local _, playerClass = UnitClass("player")
local function NPF_SunderOn()
    return CludesUI.IS_FOREVER and playerClass == "WARRIOR" and PVal("showSunderArmor") == true
end

-- Active-only include maps for engine candidates (false entries stay
-- stored but must never reach the C validator). Two maps: any-caster
-- opt-outs feed the npinc group, everything else (the default) feeds
-- npincmine (its filter string carries the PLAYER token -- the caster
-- restriction lives in the token vocabulary, not in candidate booleans).
local function NPF_ActiveIncludes(edgeSide)
    local inc = mod.NPF_Include(edgeSide)
    if not inc then
        return nil, nil
    end
    local anym = mod.NPF_IncludeAny(edgeSide)
    local m, mm
    for ident, val in pairs(inc) do
        if val then
            if anym and anym[ident] then
                m = m or {}
                m[ident] = true
            else
                mm = mm or {}
                mm[ident] = true
            end
        end
    end
    return m, mm
end

-- Candidate-table builder: the blacklist rides EVERY debuff-side group
-- (records and Show All alike) as excludeSpellIDs; extra = a record's own
-- boolean fields, copied so the stored config never aliases engine tables.
-- Exclude entries are tri-state now (true = active, false = kept but
-- disabled via the popup checkbox, nil = deleted): the engine map gets an
-- ACTIVE-ONLY copy -- a false value must not reach the C validator.
local function NPF_Cand(extra, edgeSide)
    local cand = {}
    if extra then
        for k, val in pairs(extra) do
            cand[k] = val
        end
    end
    local m
    local ex = mod.NPF_Exclude(edgeSide)
    if ex then
        for ident, val in pairs(ex) do
            if val then
                m = m or {}
                m[ident] = true
            end
        end
    end
    -- Active INCLUDES are excluded here too: the npinc/npincmine groups own
    -- their display (active in every mode), so every category / Show All
    -- group must not render its own copy.
    local incm, incmm = NPF_ActiveIncludes(edgeSide)
    if incm then
        m = m or {}
        for ident in pairs(incm) do
            m[ident] = true
        end
    end
    if incmm then
        m = m or {}
        for ident in pairs(incmm) do
            m[ident] = true
        end
    end
    -- Show-once exceptions render through their own single-frame groups
    -- (debuff side only, while the option is on), so no other group may
    -- render a copy. Option off = the id is an ordinary debuff again.
    if edgeSide ~= "cc" and PVal("hideBloodPlagueCopies") ~= false then
        for ident in pairs(NPF_ONCE_DEBUFFS) do
            m = m or {}
            m[ident] = true
        end
    end
    if edgeSide ~= "cc" and NPF_SunderOn() then
        for ident in pairs(NPF_SUNDER_IDS) do
            m = m or {}
            m[ident] = true
        end
    end
    if m then
        cand.excludeSpellIDs = m
    end
    return cand
end

-- The "np" debuff group is the SHOW ALL group only now: filtered display renders
-- through the NPF record groups (priority included -- the fixed np filter string cannot
-- carry the dedup negation chains). Its candidate set carries only the blacklist; the
-- all-flag drives its COUNT in the ensure pass.
local function DebuffCand()
    return NPF_Cand(nil, "debuff")
end

-- Declares/parks one container's NPF record groups per its kind config.
-- Declares are combat-legal (68914); stale variants park at 0 (group
-- strings are fixed; frames are never freed -- parked groups are the
-- cheap state). On the CC container the cc CATEGORY rides the existing
-- "np" group -- its filter string (HARMFUL|CROWD_CONTROL) is identical,
-- so the default config costs zero extra groups.
local function NPF_ApplyContainer(boxHolder, kindKey, styleKey, cap)
    if not boxHolder then
        return
    end
    local conf = mod.NPF_Config(kindKey)
    if not conf then
        return
    end
    local frame = conf.f or {}
    -- List side: the cc container has its own lists; the debuff
    -- container (kinds debuffs/dcc) shares the debuff-side pair.
    local edgeSide = (kindKey == "cc") and "cc" or "debuff"
    local declaredSet = boxHolder._npfGroups
    if not declaredSet then
        declaredSet = {}
        boxHolder._npfGroups = declaredSet
    end
    -- Mid-session declares on a container already bound to a live unit need an
    -- explicit parse request at the end: FinishContainer's UpdateAllAuras ran
    -- long ago, and a group added after it renders nothing until the next
    -- SetUnit (pooled re-attach) otherwise.
    local declaredNew = false
    local wanted = {}
    if not conf.all then
        local recs = NPF_Records(conf)
        for i = 1, #recs do
            local rec = recs[i]
            if not (kindKey == "cc" and rec.cat == "cc") then
                local groupKey = NPF_GKey(rec.cat, conf)
                wanted[groupKey] = true
                if not declaredSet[groupKey] then
                    AK.AddGroupToContainer(boxHolder, {
                        key = groupKey,
                        filter = rec.tokens,
                        maxFrameCount = cap,
                        candidateFilters = NPF_Cand(rec.cand, edgeSide),
                        sortMethod = SORT_IMPORTANT,
                        style = styleKey,
                        layout = {
                            elementWidth = 24,
                            elementHeight = 24,
                            elementSpacing = 4,
                            lineSpacing = 4,
                        },
                    })
                    declaredSet[groupKey] = true
                    declaredNew = true
                else
                    CludesUI.AuraKit.SetGroupCap(boxHolder, groupKey, cap)
                    boxHolder:SetAuraGroupCandidateFilters(groupKey, NPF_Cand(rec.cand, edgeSide))
                end
            end
        end
    end
    -- Show-once exceptions (NPF_ONCE_DEBUFFS): one single-frame PLAYER-cast
    -- group per id ("nponce:<id>"), includeSpellIDs = that id, maxFrameCount 1
    -- -- the engine keeps the top sorted candidate and drops the rest, which
    -- is the whole dedup. Debuff container only, and only while the option is
    -- on and the id is not blacklisted in Tracked Auras -- otherwise the group
    -- is simply not wanted (an existing one parks to 0 in the loop below; a
    -- never-declared one costs nothing). Every other debuff-side group
    -- excludes these ids while on (NPF_Cand), so this group is the sole renderer.
    if edgeSide ~= "cc" and PVal("hideBloodPlagueCopies") ~= false then
        local ex = mod.NPF_Exclude(edgeSide)
        for ident in pairs(NPF_ONCE_DEBUFFS) do
            if not (ex and ex[ident]) then
                local groupKey = "nponce:" .. ident
                wanted[groupKey] = true
                if not declaredSet[groupKey] then
                    AK.AddGroupToContainer(boxHolder, {
                        key = groupKey,
                        filter = { "HARMFUL", "PLAYER", "INCLUDE_NAME_PLATE_ONLY" },
                        maxFrameCount = 1,
                        candidateFilters = { includeSpellIDs = { [ident] = true } },
                        sortMethod = SORT_IMPORTANT,
                        style = styleKey,
                        layout = {
                            elementWidth = 24,
                            elementHeight = 24,
                            elementSpacing = 4,
                            lineSpacing = 4,
                        },
                    })
                    declaredSet[groupKey] = true
                    declaredNew = true
                else
                    CludesUI.AuraKit.SetGroupCap(boxHolder, groupKey, 1)
                end
            end
        end
    end
    -- Sunder Armor (Forever warriors, opt-in): any caster, one icon. Ids the
    -- user already lists in Tracked Auras keep going through those lists.
    if edgeSide ~= "cc" and NPF_SunderOn() then
        local ex, inc = mod.NPF_Exclude(edgeSide), mod.NPF_Include(edgeSide)
        local ids
        for ident in pairs(NPF_SUNDER_IDS) do
            if not (ex and ex[ident]) and not (inc and inc[ident]) then
                ids = ids or {}
                ids[ident] = true
            end
        end
        if ids then
            wanted.npsunder = true
            if not declaredSet.npsunder then
                AK.AddGroupToContainer(boxHolder, {
                    key = "npsunder",
                    filter = { "HARMFUL", "INCLUDE_NAME_PLATE_ONLY" },
                    maxFrameCount = 1,
                    candidateFilters = { includeSpellIDs = ids },
                    sortMethod = SORT_IMPORTANT,
                    style = styleKey,
                    layout = {
                        elementWidth = 24,
                        elementHeight = 24,
                        elementSpacing = 4,
                        lineSpacing = 4,
                    },
                })
                declaredSet.npsunder = true
                declaredNew = true
            else
                boxHolder:SetAuraGroupCandidateFilters("npsunder", { includeSpellIDs = ids })
                CludesUI.AuraKit.SetGroupCap(boxHolder, "npsunder", 1)
            end
        end
    end
    for groupKey in pairs(declaredSet) do
        if groupKey ~= "npinc" and groupKey ~= "npincmine" and not wanted[groupKey] then
            CludesUI.AuraKit.SetGroupCap(boxHolder, groupKey, 0)
        end
    end
    local npOn
    if kindKey == "cc" then
        npOn = conf.all or frame.cc or false
    else
        npOn = conf.all or false
    end
    -- Blacklist on the np group too (both containers; the debuff cfg pass
    -- also re-drives this -- same values, dirty-mark cheap).
    boxHolder:SetAuraGroupCandidateFilters("np", NPF_Cand(nil, edgeSide))
    CludesUI.AuraKit.SetGroupCap(boxHolder, "np", npOn and cap or 0)
    -- Include list (Tracked Auras popup): the side's own groups on this
    -- container. They stay ACTIVE in every mode, Show All included -- the
    -- np group's fixed filter string is PLAYER-cast (and !CROWD_CONTROL on
    -- the debuff container), so an included spell cast by someone else or
    -- flagged CC can only render here; every other group excludes the
    -- included ids via NPF_Cand. Candidates re-drive live; count follows
    -- whether any entry is active. Two groups because caster scope lives
    -- in the filter STRING (fixed at declaration): npinc = any caster,
    -- npincmine = PLAYER token for entries flagged Only My Casts.
    local incm, incmm = NPF_ActiveIncludes(edgeSide)
    if incm and not declaredSet.npinc then
        AK.AddGroupToContainer(boxHolder, {
            key = "npinc",
            filter = { "HARMFUL", "INCLUDE_NAME_PLATE_ONLY" },
            maxFrameCount = cap,
            candidateFilters = { includeSpellIDs = incm },
            sortMethod = SORT_IMPORTANT,
            style = styleKey,
            layout = {
                elementWidth = 24,
                elementHeight = 24,
                elementSpacing = 4,
                lineSpacing = 4,
            },
        })
        declaredSet.npinc = true
        declaredNew = true
    elseif declaredSet.npinc then
        if incm then
            boxHolder:SetAuraGroupCandidateFilters("npinc", { includeSpellIDs = incm })
        end
        CludesUI.AuraKit.SetGroupCap(boxHolder, "npinc", incm and cap or 0)
    end
    if incmm and not declaredSet.npincmine then
        AK.AddGroupToContainer(boxHolder, {
            key = "npincmine",
            filter = { "HARMFUL", "PLAYER", "INCLUDE_NAME_PLATE_ONLY" },
            maxFrameCount = cap,
            candidateFilters = { includeSpellIDs = incmm },
            sortMethod = SORT_IMPORTANT,
            style = styleKey,
            layout = {
                elementWidth = 24,
                elementHeight = 24,
                elementSpacing = 4,
                lineSpacing = 4,
            },
        })
        declaredSet.npincmine = true
        declaredNew = true
    elseif declaredSet.npincmine then
        if incmm then
            boxHolder:SetAuraGroupCandidateFilters("npincmine", { includeSpellIDs = incmm })
        end
        CludesUI.AuraKit.SetGroupCap(boxHolder, "npincmine", incmm and cap or 0)
    end
    -- One parse covers every group declared this pass. Only for containers
    -- bound to a live unit (BindContainer's stamp): at pool build the unit
    -- is "none" and the attach-time SetUnit/UpdateAllAuras pair owns it.
    if declaredNew and boxHolder._npcBoundUnit then
        boxHolder:UpdateAllAuras()
    end
end

local function NPF_EnsureRecords(b)
    NPF_ApplyContainer(b.containers.debuffs, NPF_DebuffKind(), "np:debuffs", PVal("maxDebuffs") or 5)
    NPF_ApplyContainer(b.containers.cc, "cc", "np:cc", 2)
end

-- Bundle construction is split into one job per container for the shared AuraKit build
-- scheduler: each container's group is a 10-button engine batch (~4-6ms), and a whole
-- bundle in one gulp was a per-frame spike during the post-login pool build.
local function CreateBundleShell()
    local holderFrame = CreateFrame("Frame", nil, UIParent)
    holderFrame:Hide()
    holderFrame:SetSize(1, 1)
    holderFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", -200, -200)

    return { holder = holderFrame, containers = {} }
end

-- Builds one bundle container from a pre-born shell when available (group add + finish
-- are combat-legal -- probe T1/T1b), else creates fresh (OOC only; the callers guard).
local function BundleContainer(b, kindName, groupSpec)
    -- Single spec (has .key) or an ARRAY of specs (the buffs container's
    -- glow/plain group pair).
    local specs = groupSpec[1] and groupSpec or { groupSpec }
    local shell = b.shells and b.shells[kindName]
    if shell then
        b.shells[kindName] = nil
        for i = 1, #specs do
            AK.AddGroupToContainer(shell, specs[i])
        end
        AK.FinishContainer(shell, "none")
        return shell
    end
    return (
        AK.CreateContainer(b.holder, "none", {
            point = { "CENTER", b.holder, "CENTER" },
            groups = specs,
        })
    )
end

-- Enemy buff narrowing belongs in the FILTER STRING, not in candidateFilters. A candidate
-- filter is a Lua compare against auraData.isStealable, and aura data on an enemy unit is
-- SECRET in instanced PvP: there "isStealable ~= true" is true for every buff, so the group
-- renders nothing. (Blizzard's own nameplate rule survives the same secrecy only because it
-- tests "== false" -- an unreadable aura is kept, not dropped.) DISPELLABLE is evaluated by
-- the engine in C, like every filter string, so it stays plain under restriction -- which is
-- also why the debuff row never broke. Clients predating the token keep the old candidate
-- filter: no worse than before, and PvE is unaffected either way.
-- DISPELLABLE and IMPORTANT are declared up top, next to PurgeGlowActive --
-- which reads DISPELLABLE and is defined far above this point (a file-scope
-- local would be invisible to it down here).

-- Enemy Buff Filter mode (npEnemyBuffFilter): "important" is the retail
-- DEFAULT (the retired showAllEnemyBuffs key is an inert orphan, never
-- migrated and never read; the removed "all" value normalizes to important
-- the same way), "showall" the WoW Forever one (defaults table).
-- UNION SEMANTICS: a single filter string ANDs its tokens, so the OR lives in
-- the group split. TWO groups render the row:
-- "np" = ALL dispellable buffs (purgeables AND enrages -- the engine's
-- DISPELLABLE token is class-independent; this group carries the dispel glow
-- style), "npnb" = the non-dispellable remainder (plain style; !DISPELLABLE
-- keeps the union overlap-free), narrowed to IMPORTANT in Important mode and
-- whole in Show All mode, parked at 0 in Dispellable mode. Important mode
-- therefore shows important OR dispellable, Show All every buff, and
-- Dispellable the glow group alone. On retail, Dispellable By Me
-- (BuffDispelByMe) narrows "dispellable" to the group's own dispels in
-- Important and Dispellable mode: both groups then take RAID_DISPELLABLE in
-- place of DISPELLABLE, so they stay exact complements. All are composed
-- filter STRINGS with INCLUDE_NAME_PLATE_ONLY (matches Blizzard's own
-- buffFilterString) -- C-evaluated, so the split holds on secret enemy data in
-- instanced PvP and the glow needs no per-aura signal (the machinery #1509
-- deleted). The Dispel Glow setting never touches these filters -- it is only
-- the style the "np" group wears, so every shown dispellable buff glows.
local function BuffMode()
    local m = PVal("npEnemyBuffFilter")
    if m == "dispellable" or m == "showall" then
        return m
    end
    return "important"
end

-- Important or Only Dispellable with "Dispellable By Me" on (retail only;
-- Show All never reads it).
local function BuffDispelByMe()
    local mode = BuffMode()
    return not CludesUI.IS_FOREVER
        and RAID_DISPELLABLE ~= nil
        and mode ~= "showall"
        and PVal("npEnemyBuffDispelByMe") == true
end

local function BuffFilterGlow()
    local t = { "HELPFUL", "INCLUDE_NAME_PLATE_ONLY" }
    -- Stale-client shape only: without the DISPELLABLE token the union cannot
    -- be expressed, so Important mode keeps the old curated single group.
    if BuffMode() == "important" and IMPORTANT and not DISPELLABLE then
        t[#t + 1] = IMPORTANT
    end
    if DISPELLABLE then
        t[#t + 1] = BuffDispelByMe() and RAID_DISPELLABLE or DISPELLABLE
    end
    return t
end

-- nil = the plain group has nothing to show (Dispellable mode, or a client
-- without the DISPELLABLE token, where no complement can be expressed).
-- Important narrows the remainder to IMPORTANT; Show All keeps all of it.
local function BuffFilterPlain()
    local mode = BuffMode()
    if mode == "dispellable" or not DISPELLABLE then
        return nil
    end
    local t = { "HELPFUL", "INCLUDE_NAME_PLATE_ONLY" }
    if mode == "important" and IMPORTANT then
        t[#t + 1] = IMPORTANT
    end
    -- The same token the glow group uses, so the two stay exact complements.
    t[#t + 1] = "!" .. (BuffDispelByMe() and RAID_DISPELLABLE or DISPELLABLE)
    return t
end

-- Stale-client fallback only (no DISPELLABLE token): the old isStealable
-- candidate approximates the glow group's narrowing.
local function BuffCand()
    if DISPELLABLE then
        return nil
    end
    return { isStealable = true }
end

local function AddBundleDebuffs(b)
    b.containers.debuffs = BundleContainer(b, "debuffs", {
        key = "np",
        filter = { "HARMFUL", "PLAYER", "INCLUDE_NAME_PLATE_ONLY", "!CROWD_CONTROL" },
        maxFrameCount = PVal("maxDebuffs") or 5,
        sortMethod = DebuffSort(),
        candidateFilters = DebuffCand(),
        style = "np:debuffs",
        layout = { elementWidth = 26, elementHeight = 26, elementSpacing = 4, lineSpacing = 4 },
    })
end

-- One glow-group spec. idx 1 is the whole dispellable row while unsplit and
-- the Magic half while split; idx 2 is the non-Magic (enrage) half, declared
-- only while the split is on (it parks at 0 frames afterwards -- groups are
-- never removed). Both halves share the mode's filter STRING; only the
-- candidate differs.
function NPB.GlowSpec(position)
    local styleKey = (position == 2) and "np:buffs2" or "np:buffs"
    local cand
    if NPB.Split() then
        cand = (position == 2) and NPB.NONMAGIC or NPB.MAGIC
    else
        cand = BuffCand()
    end
    return {
        key = (position == 2) and "np2" or "np",
        filter = BuffFilterGlow(),
        maxFrameCount = 4,
        sortMethod = SORT_IMPORTANT,
        candidateFilters = cand,
        style = styleKey,
        -- Purge glow: built on first paint so a button born while the glow
        -- is already on does not wait for the next style pass.
        extraInit = function(button, dropdown)
            local look = AK.styles[styleKey]
            if look and look.purgeGlow then
                ApplyNPBuffExtra(button, dropdown, look)
            end
        end,
        layout = { elementWidth = 24, elementHeight = 24, elementSpacing = 4, lineSpacing = 4 },
    }
end

-- Declares or parks the non-Magic glow group to match the current split, on
-- containers that already existed when capability / restriction / the type
-- color option / the dispel glow style changed.
function NPB.Apply(boxHolder)
    if not boxHolder then
        return
    end
    local split = NPB.Split()
    if split and not boxHolder._npbSplit then
        AK.AddGroupToContainer(boxHolder, NPB.GlowSpec(2))
        boxHolder._npbSplit = true
        -- The new group carries the declaration's placeholder sizing until an
        -- anchor pass reaches it, and that pass skips containers whose layout
        -- stamp is current -- so drop the stamp.
        boxHolder._npcGeoGen = nil
        -- A group added after FinishContainer's parse renders nothing until
        -- the next SetUnit unless this container is asked to re-parse now.
        if boxHolder._npcBoundUnit then
            boxHolder:UpdateAllAuras()
        end
    elseif boxHolder._npbSplit then
        CludesUI.AuraKit.SetGroupCap(boxHolder, "np2", split and 4 or 0)
    end
end

local function AddBundleBuffs(b)
    -- Glow group(s) + plain remainder (BuffMode doctrine above): the
    -- dispellable set carries the dispel glow style (split by dispel type
    -- while NPB.Split holds), the important remainder renders plain.
    -- Declaration is add-only, so the plain group is ALWAYS declared (a mode
    -- flip needs it live) and parked at 0 while the mode has no remainder.
    -- Display order: Magic, then enrages, then plain; important-sorted
    -- within each group.
    local plainToks = BuffFilterPlain()
    local plainDecl = plainToks
    if not plainDecl then
        plainDecl = { "HELPFUL", "INCLUDE_NAME_PLATE_ONLY" }
        if DISPELLABLE then
            plainDecl[#plainDecl + 1] = "!" .. DISPELLABLE
        end
    end
    local specs = { NPB.GlowSpec(1) }
    if NPB.Split() then
        specs[#specs + 1] = NPB.GlowSpec(2)
    end
    specs[#specs + 1] = {
        key = "npnb",
        filter = plainDecl,
        maxFrameCount = plainToks and 4 or 0,
        sortMethod = SORT_IMPORTANT,
        style = "np:buffsplain",
        layout = { elementWidth = 24, elementHeight = 24, elementSpacing = 4, lineSpacing = 4 },
    }
    b.containers.buffs = BundleContainer(b, "buffs", specs)
    if #specs > 2 then
        b.containers.buffs._npbSplit = true
    end
end

local function AddBundleCC(b)
    b.containers.cc = BundleContainer(b, "cc", {
        key = "np",
        filter = { "HARMFUL", "CROWD_CONTROL" },
        maxFrameCount = 2,
        sortMethod = SORT_DEFAULT,
        style = "np:cc",
        layout = { elementWidth = 24, elementHeight = 24, elementSpacing = 4, lineSpacing = 4 },
    })
end

-- A skeleton = holder + three bare container shells, born in the early
-- load window (PLAYER_LOGIN precedes combat re-engagement on every reload
-- path -- the suite's positioning trick). All later bundle work is then
-- combat-legal group adds/finishes.
local function CreateBundleSkeleton()
    local b = CreateBundleShell()
    b.shells = {
        debuffs = AK.CreateContainerShell(b.holder, { point = { "CENTER", b.holder, "CENTER" } }),
        buffs = AK.CreateContainerShell(b.holder, { point = { "CENTER", b.holder, "CENTER" } }),
        cc = AK.CreateContainerShell(b.holder, { point = { "CENTER", b.holder, "CENTER" } }),
    }
    return b
end
local skeletons = {}

local function SafeClearUnit(boxHolder)
    if not pcall(boxHolder.SetUnit, boxHolder, "none") then
        pcall(boxHolder.SetUnit, boxHolder, nil)
    end
end

-- Unit binding follows the SLOT setting: a container whose slot is "none" stays parked
-- on unit "none" and costs nothing -- SetUnit/UpdateAllAuras are synchronous engine
-- parses billed to this addon, and plates churn constantly in combat, so binding all
-- three containers unconditionally charged the full parse three times per spawn
-- regardless of how many rows are actually displayed. Detach clears the flag, so a
-- pooled bundle always re-binds fresh at its next attach.
local function BindContainer(c, unitToken, slotValue)
    if not c then
        return
    end -- conditional bundles: row disabled at build time
    if slotValue and slotValue ~= "none" then
        if not c._npcBoundUnit then
            c._npcBoundUnit = true
            c:SetUnit(unitToken)
            c:UpdateAllAuras()
        end
    elseif c._npcBoundUnit then
        c._npcBoundUnit = nil
        SafeClearUnit(c)
    end
end

------------------------------------------------------------------------------
-- Anchoring: each aura slot's placement, with container flow.
-- top/bottom center-pin (self-centering rows); left/right chain outward
-- from the health bar; topleft/topright corner-pin with per-slot growth.
------------------------------------------------------------------------------

local function FlowDir(token)
    local FD = AnchorUtil.FlowDirection
    if token == "LEFT" then
        return FD.Left
    end
    if token == "UP" then
        return FD.Up
    end
    if token == "DOWN" then
        return FD.Down
    end
    return FD.Right
end

local function TopAnchorFor(backing)
    local topElement = (mod.GetTextSlot and mod.GetTextSlot("textSlotTop")) or "none"
    if mod.IsNameElement and mod.IsNameElement(topElement) then
        return backing.name or backing.health
    end
    if topElement == "healthNumber" then
        return backing.hpNumber or backing.health
    end
    if topElement == "level" then
        return backing.levelText or backing.health
    end
    if topElement == "targetOfTarget" then
        return backing.totText or backing.health
    end
    if topElement == "custom" then
        return backing.customTop or backing.health
    end
    if topElement ~= "none" then
        return backing.hpText or backing.health
    end
    return backing.health, true -- health-anchored: add class power push
end

local function AnchorNPContainer(boxHolder, kindName, backing, slotValue)
    if not boxHolder then
        return
    end
    boxHolder:ClearAllPoints()
    if not slotValue or slotValue == "none" then
        boxHolder:SetShown(false)
        return
    end
    boxHolder:SetShown(kindName ~= "buffs" or boxHolder._npcAttackable ~= false)

    local px = NPSize(kindName)
    local height = NPHeight(kindName, px)
    local spacing = (mod.GetAuraSpacing and mod.GetAuraSpacing(kindName == "cc" and "ccs" or kindName)) or 4
    local xOff, yOff = 0, 0
    if mod.GetAuraSlotOffsets then
        xOff, yOff = mod.GetAuraSlotOffsets(
            kindName == "debuffs" and "debuffSlot" or kindName == "buffs" and "buffSlot" or "ccSlot"
        )
    end

    local anchorPoint, gH, gV, rowWidth
    if slotValue == "top" then
        local anchor, healthAnchored = TopAnchorFor(backing)
        local debuffY = (mod.GetDebuffYOffset and mod.GetDebuffYOffset()) or 2
        local cpPush = (healthAnchored and mod.NP_ClassPowerTopPush) and mod.NP_ClassPowerTopPush(backing)
            or 0
        boxHolder:SetPoint("BOTTOM", anchor, "TOP", xOff, debuffY + cpPush + yOff)
        anchorPoint, gH, gV = "BOTTOMLEFT", "RIGHT", "UP"
    elseif slotValue == "bottom" then
        boxHolder:SetPoint("TOP", backing.cast or backing.health, "BOTTOM", xOff, -2 + yOff)
        anchorPoint, gH, gV = "TOPLEFT", "RIGHT", "DOWN"
    elseif slotValue == "left" or slotValue == "right" then
        -- Classic WoW UI: gap off the border art, not the bare bar edge; WoW
        -- Forever's level box on the right (ns.NP_ClassicSide, 0 on every other
        -- style). During a cast the full-size spell icon pushes the row out past
        -- it where the two meet (the row spans its Y offset up by one icon);
        -- the push is kept for NPC_PlaceSideRows.
        local push = mod.NP_FullIconPush(backing, slotValue, yOff, yOff + height)
        boxHolder._npcPush = push
        local sideOff = ((mod.GetSideAuraXOffset and mod.GetSideAuraXOffset()) or 2)
            + ((mod.NP_ClassicSide and mod.NP_ClassicSide(slotValue)) or 0)
            + push
        if slotValue == "left" then
            boxHolder:SetPoint("BOTTOMRIGHT", backing.health, "BOTTOMLEFT", -sideOff + xOff, yOff)
            anchorPoint, gH, gV = "BOTTOMRIGHT", "LEFT", "UP"
        else
            boxHolder:SetPoint("BOTTOMLEFT", backing.health, "BOTTOMRIGHT", sideOff + xOff, yOff)
            anchorPoint, gH, gV = "BOTTOMLEFT", "RIGHT", "UP"
        end
    elseif slotValue == "topleft" or slotValue == "topright" then
        local debuffY = (mod.GetDebuffYOffset and mod.GetDebuffYOffset()) or 2
        local cpPush = mod.NP_ClassPowerTopPush and mod.NP_ClassPowerTopPush(backing) or 0
        local growth = PVal(slotValue .. "SlotGrowth") or (slotValue == "topleft" and "left" or "right")
        local corner = (slotValue == "topleft") and "BOTTOMLEFT" or "BOTTOMRIGHT"
        local healthCorner = (slotValue == "topleft") and "TOPLEFT" or "TOPRIGHT"
        -- Above the corner's Top Left / Top Right text while it shows one.
        boxHolder:SetPoint(
            corner,
            backing.health,
            healthCorner,
            xOff,
            debuffY + cpPush + mod.NP_TopCornerLift(slotValue) + yOff
        )
        anchorPoint = corner
        if growth == "up" then
            gH = (slotValue == "topleft") and "RIGHT" or "LEFT"
            gV = "UP"
            rowWidth = px + 0.4
        else
            gH = (growth == "left") and "LEFT" or "RIGHT"
            gV = "UP"
        end
    else
        boxHolder:SetShown(false)
        return
    end

    -- Active cast lockout: the lockout icon holds the CC row's first position, so the
    -- CC container chains off its far edge instead of the health anchor (top/bottom
    -- rows trade their centering for the lockout's few seconds -- accepted).
    if kindName == "cc" then
        local lk = backing.npcLockout
        if lk and lk:IsShown() then
            boxHolder:ClearAllPoints()
            if slotValue == "left" then
                boxHolder:SetPoint("BOTTOMRIGHT", lk, "BOTTOMLEFT", -spacing, 0)
            elseif slotValue == "topleft" or slotValue == "topright" then
                local growth = PVal(slotValue .. "SlotGrowth") or (slotValue == "topleft" and "left" or "right")
                if growth == "up" then
                    local edgeSide = (slotValue == "topleft") and "LEFT" or "RIGHT"
                    boxHolder:SetPoint("BOTTOM" .. edgeSide, lk, "TOP" .. edgeSide, 0, spacing)
                elseif growth == "left" then
                    boxHolder:SetPoint("BOTTOMRIGHT", lk, "BOTTOMLEFT", -spacing, 0)
                else
                    boxHolder:SetPoint("BOTTOMLEFT", lk, "BOTTOMRIGHT", spacing, 0)
                end
            else -- top, bottom, right: chain rightward
                boxHolder:SetPoint("BOTTOMLEFT", lk, "BOTTOMRIGHT", spacing, 0)
            end
        end
    end

    -- Everything below derives from slot/geometry settings alone (never
    -- from the plate), so a bundle whose stamp matches the current layout
    -- generation already carries this exact engine state from its last
    -- attach -- skip the setters (plate churn re-attaches bundles
    -- constantly; unconditional re-drives were per-spawn dirty marks).
    if boxHolder._npcGeoGen ~= geoGen or boxHolder._npcSlotVal ~= slotValue then
        boxHolder._npcGeoGen = geoGen
        boxHolder._npcSlotVal = slotValue

        AK.SetContainerAnchor(boxHolder, anchorPoint)
        AK.SetContainerGrowth(boxHolder, FlowDir(gH), FlowDir(gV))
        AK.SetContainerRowWidth(boxHolder, rowWidth)
        local gLayout = {
            elementWidth = px,
            elementHeight = height,
            elementSpacing = spacing,
            lineSpacing = spacing,
        }
        boxHolder:SetAuraGroupLayout("np", gLayout)
        -- The buff row's non-Magic glow group shares the row's element sizing.
        if boxHolder._npbSplit then
            boxHolder:SetAuraGroupLayout("np2", gLayout)
        end
        -- NPF record groups share the row's element sizing.
        if boxHolder._npfGroups then
            for groupKey in pairs(boxHolder._npfGroups) do
                boxHolder:SetAuraGroupLayout(groupKey, gLayout)
            end
        end

        -- Aura tier of the flattened plate render order (text 900 > auras 800),
        -- honoring the per-slot Raise Strata toggle like the legacy pools.
        local raise = mod.GetSlotRaiseStrata and mod.GetSlotRaiseStrata(slotValue)
        boxHolder:SetFrameStrata(raise and "HIGH" or "MEDIUM")
        boxHolder:SetFrameLevel(800)
    end

    -- Elements sharing the slot: with the row at its own spot, the chain places them (and
    -- the row itself, unless it is the slot's first shown element). One count for a slot
    -- that holds nothing else.
    mod.NP_CoreChain(backing, slotValue)
end

-- Cast-lockout pseudo-aura (kick lockout displayed as a CC icon): armed by
-- the core's cast machinery (ShowCastLockout -- readable, cast-driven, no
-- aura reads), rendered here since the legacy CC row is gone. The frame is
-- OUR child of OUR plate object; positioned exactly at the CC slot pin.
local function PositionLockout(backing, frame, slotValue)
    frame:ClearAllPoints()
    local xOff, yOff = mod.GetAuraSlotOffsets("ccSlot")
    if slotValue == "top" then
        local anchor, healthAnchored = TopAnchorFor(backing)
        local debuffY = (mod.GetDebuffYOffset and mod.GetDebuffYOffset()) or 2
        local cpPush = (healthAnchored and mod.NP_ClassPowerTopPush) and mod.NP_ClassPowerTopPush(backing)
            or 0
        frame:SetPoint("BOTTOM", anchor, "TOP", xOff, debuffY + cpPush + yOff)
    elseif slotValue == "bottom" then
        frame:SetPoint("TOP", backing.cast or backing.health, "BOTTOM", xOff, -2 + yOff)
    elseif slotValue == "left" or slotValue == "right" then
        -- Classic WoW UI's border and the full-size spell icon push it out, as
        -- the containers above.
        local sideOff = ((mod.GetSideAuraXOffset and mod.GetSideAuraXOffset()) or 2)
            + ((mod.NP_ClassicSide and mod.NP_ClassicSide(slotValue)) or 0)
            + mod.NP_FullIconPush(backing, slotValue, yOff, yOff + (NPHeight("cc", NPSize("cc"))))
        if slotValue == "left" then
            frame:SetPoint("BOTTOMRIGHT", backing.health, "BOTTOMLEFT", -sideOff + xOff, yOff)
        else
            frame:SetPoint("BOTTOMLEFT", backing.health, "BOTTOMRIGHT", sideOff + xOff, yOff)
        end
    else -- topleft / topright (above the corner's text while it shows one)
        local debuffY = (mod.GetDebuffYOffset and mod.GetDebuffYOffset()) or 2
        local cpPush = mod.NP_ClassPowerTopPush and mod.NP_ClassPowerTopPush(backing) or 0
        local corner = (slotValue == "topleft") and "BOTTOMLEFT" or "BOTTOMRIGHT"
        local hc = (slotValue == "topleft") and "TOPLEFT" or "TOPRIGHT"
        frame:SetPoint(corner, backing.health, hc, xOff, debuffY + cpPush + mod.NP_TopCornerLift(slotValue) + yOff)
    end
end

------------------------------------------------------------------------------
-- Core Positions chains: the elements sharing one slot (the raid marker, the Rare/Quest
-- indicator, the Quest Objective Text, the faction badge, the three aura rows), laid out one
-- after another in the slot's order (<pos>SlotOrder: the option keys joined by commas; unset
-- = the default order), <pos>SlotElementSpacing apart (unset = the first aura row's Spacing
-- in that order, else the global aura spacing). A slot holding fewer than two of them costs
-- one count, and every element keeps the placement its own pass gave it. With two or more,
-- every pass that places a member (UpdateRaidIcon / UpdateClassification / UpdateQuestText /
-- UpdateFaction in Name.lua; AnchorNPContainer: attach, re-anchors, the lockout, the cast
-- icon push) ends here, and the chain places every shown member again: the first by its own
-- rule (the pivot), each later one off the one before it. Left and Right grow outward, the
-- corners by the slot's Grow, Top and Bottom around the first shown aura row, which keeps
-- its centred spot: the members before it in the order hang off its left edge, the ones
-- after off its right. Every element keeps its own size and height (an icon centred on the
-- bar at the size its update gave it, _npSz; a row on the bar's bottom), so alone or chained
-- it sits where it always did. A hidden member (no marker, no mark, no text, no badge) is
-- skipped, so the chain closes up; an empty row
-- keeps its spacing (its width is engine-secret). The cast-lockout icon leads the Crowd
-- Control row, which chains off it in the chain's direction. A member after a row hangs
-- from the row's engine-sized corner, which only an aspect-born frame may (plate.coreHost,
-- PlatePool): without the host it keeps its own spot. NPC_SideRow hands the target arrows
-- and the Kick Tracker the chain's outermost element on a side.
------------------------------------------------------------------------------
local Chain = {
    DEFAULT = "debuffs,buffs,ccs,raidmarker,rare,quest,questtext,faction",
    -- Option key -> member (rare and quest are one frame).
    MEMBER = {
        debuffs = "debuffs",
        buffs = "buffs",
        ccs = "cc",
        raidmarker = "raid",
        rare = "class",
        quest = "class",
        questtext = "qtext",
        faction = "faction",
    },
    orderMemo = {}, -- [pos] = { src = the saved string, list = { member, ... } }
    keys = {}, -- [pos] = the slot's setting keys (no string building per pass)
    m = {}, -- the slot's members in order (ChainMembers)
    -- The plate's shown members (ChainShown): the frame the chain places, the frame the
    -- next member hangs off, the bottom edge of the member's own placement, row or icon,
    -- the member id, an icon's height (0 for a row).
    lead = {},
    trail = {},
    base = {},
    row = {},
    id = {},
    sz = {},
    busy = false,
}

local function ChainKeys(place)
    local k = Chain.keys[place]
    if not k then
        k = {
            order = place .. "SlotOrder",
            spacing = place .. "SlotElementSpacing",
            growth = place .. "SlotGrowth",
        }
        Chain.keys[place] = k
    end
    return k
end

-- The slot's order: its saved string parsed once per value; members a saved order lacks
-- follow in the default order, except the Quest Objective Text, which a saved order that
-- holds the Quest Indicator but not it reads right after the Quest Indicator.
local function ChainOrder(place)
    local source = PVal(ChainKeys(place).order)
    if type(source) ~= "string" then
        source = Chain.DEFAULT
    end
    local memo = Chain.orderMemo[place]
    if memo and memo.src == source then
        return memo.list
    end
    local entries, seen = {}, {}
    local function add(ident)
        if ident and not seen[ident] then
            seen[ident] = true
            entries[#entries + 1] = ident
        end
    end
    local function take(s, textAfterQuest)
        for auraKey in string.gmatch(s, "[^,]+") do
            add(Chain.MEMBER[auraKey])
            if textAfterQuest and auraKey == "quest" then
                add("qtext")
            end
        end
    end
    local hasText = false
    for auraKey in string.gmatch(source, "[^,]+") do
        if auraKey == "questtext" then
            hasText = true
            break
        end
    end
    take(source, not hasText)
    take(Chain.DEFAULT)
    Chain.orderMemo[place] = { src = source, list = entries }
    return entries
end

-- The members the slot holds, in its order, into Chain.m; returns their count. A member
-- counts while its own position key names the slot: the badge riding the Rare/Quest
-- indicator is part of that member, Crowd Control inside the debuff row is the debuff row's.
-- The Rare/Quest member counts only while one of its halves is on or the badge rides it.
local function ChainMembers(place)
    local m = Chain.m
    local num = 0
    local ds, bs, cs = mod.GetAuraSlots()
    local raid, class = mod.GetRaidMarkerPos(), mod.GetClassificationSlot()
    if
        PVal("classificationHideRare")
        and not mod.NP_QuestIconOn()
        and PVal("classificationIncludeFaction") ~= true
    then
        class = "none"
    end
    local fac = (PVal("classificationIncludeFaction") ~= true) and mod.NP_GetFactionSlot() or "none"
    local qtext = mod.NP_GetQuestTextSlot()
    local sequence = ChainOrder(place)
    for i = 1, #sequence do
        local ident = sequence[i]
        local at
        if ident == "debuffs" then
            at = ds
        elseif ident == "buffs" then
            at = bs
        elseif ident == "cc" then
            at = cs
        elseif ident == "raid" then
            at = raid
        elseif ident == "class" then
            at = class
        elseif ident == "qtext" then
            at = qtext
        else
            at = fac
        end
        if at == place then
            num = num + 1
            m[num] = ident
        end
    end
    for i = num + 1, #m do
        m[i] = nil
    end
    return num
end

-- Whether the slot holds two or more members (the chain places its elements).
function mod.NP_CoreChained(place)
    return place ~= nil and place ~= "none" and ChainMembers(place) >= 2
end
-- The slot's member count (the options show Element Spacing from two).
function mod.NP_CoreMemberCount(place)
    if not place or place == "none" then
        return 0
    end
    return ChainMembers(place)
end

-- The spacing between the slot's elements: its own, else the first aura row's Spacing in
-- the slot's order, else the global aura spacing. ChainMembers has filled Chain.m.
local function ChainSpacing(place)
    local val = PVal(ChainKeys(place).spacing)
    if type(val) == "number" then
        return val
    end
    local m = Chain.m
    for i = 1, #m do
        local ident = m[i]
        if ident == "debuffs" or ident == "buffs" or ident == "cc" then
            return mod.GetAuraSpacing((ident == "cc") and "ccs" or ident) or 4
        end
    end
    return mod.GetAuraSpacing() or 4
end
-- The options' Element Spacing row reads the same rule.
function mod.NP_CoreElementSpacing(place)
    if not place or place == "none" then
        return 0
    end
    ChainMembers(place)
    return ChainSpacing(place)
end

-- A member's bottom edge over the slot's reference, as its own placement puts it: a row's
-- Y offset, an icon's centred on the bar at Left and Right; at the corners the row sits a
-- Debuff Y Offset up, the raid marker on the corner, the indicators 2 up (the class power
-- push, shared, cancels). Top and Bottom align every member to the one before it.
local function ChainBase(place, ident, isRow, sz, yOff, barH)
    if place == "left" or place == "right" then
        if isRow then
            return yOff
        end
        return yOff + barH / 2 - sz / 2
    elseif place == "topleft" or place == "topright" then
        if isRow then
            return mod.GetDebuffYOffset() + yOff
        end
        if ident == "raid" then
            return yOff
        end
        return 2 + yOff
    end
    return 0
end

-- The plate's shown members of the slot, in order, into Chain.lead / trail / base / row /
-- id / sz; returns their count. A row counts only while shown and last placed in this very
-- slot (IsSideRow); the Crowd Control row behind its lockout icon is led by the icon. An
-- icon's height is the one its update gave it (_npSz), else the slot's size.
local function ChainShown(backing, place, num)
    local b = isActive[backing]
    local _, yOff = mod.GetSlotOffsets(place)
    local barH = mod.GetHealthBarHeight()
    local k = 0
    for i = 1, num do
        local ident = Chain.m[i]
        local leadSlot, trail, isRow
        if ident == "raid" then
            leadSlot = backing.raidFrame
        elseif ident == "class" then
            leadSlot = backing.classFrame
            -- Rare/Quest + Faction with no mark: the badge stands in for the pair.
            if not (leadSlot and leadSlot:IsShown()) and PVal("classificationIncludeFaction") == true then
                leadSlot = backing.factionFrame
            end
        elseif ident == "qtext" then
            leadSlot = backing.questTextFrame
        elseif ident == "faction" then
            leadSlot = backing.factionFrame
        else
            local c = b and b.containers[ident]
            if c and c._npcSlotVal == place then
                leadSlot, isRow = c, true
                if ident == "cc" then
                    local lk = backing.npcLockout
                    if lk and lk:IsShown() then
                        trail = c
                        leadSlot = lk
                    end
                end
            end
        end
        if leadSlot and leadSlot:IsShown() then
            k = k + 1
            local sz = 0
            if not isRow then
                sz = leadSlot._npSz or mod.GetSlotSize(place)
            end
            Chain.lead[k], Chain.trail[k], Chain.row[k], Chain.id[k] =
                leadSlot, trail or leadSlot, isRow or false, ident
            Chain.sz[k] = sz
            Chain.base[k] = ChainBase(place, ident, isRow, sz, yOff, barH)
        end
    end
    for i = k + 1, #Chain.lead do
        Chain.lead[i], Chain.trail[i], Chain.base[i], Chain.row[i], Chain.id[i] = nil, nil, nil, nil, nil
        Chain.sz[i] = nil
    end
    return k
end

-- The chain's direction at the slot: outward from the bar at Left and Right, the slot's
-- Grow at the corners, rightward from the pivot at Top and Bottom (the members before the
-- pivot run leftward).
local function ChainDir(place)
    if place == "left" then
        return "left"
    end
    if place == "topleft" or place == "topright" then
        local g = PVal(ChainKeys(place).growth) or ((place == "topleft") and "left" or "right")
        if g == "up" or g == "left" then
            return g
        end
    end
    return "right"
end

-- Places member i by its own rule: an icon by the slot icon placer (Name.lua), a row by
-- AnchorNPContainer, behind its lockout icon where one shows (PositionLockout).
local function ChainPlaceOwn(backing, place, i)
    local ident, leadSlot = Chain.id[i], Chain.lead[i]
    if Chain.row[i] then
        local c = Chain.trail[i]
        if leadSlot ~= c then
            PositionLockout(backing, leadSlot, place)
        end
        AnchorNPContainer(c, ident, backing, place)
    else
        local xOff, yOff = mod.GetSlotOffsets(place)
        mod.NP_PlaceSlotIcon(backing, leadSlot, place, xOff, yOff, (ident == "raid") and 0 or 2, Chain.sz[i])
    end
end

-- An icon keeps its own placement's units (PP.Point); a row or the lockout icon the
-- containers' plain ones.
local function ChainPoint(frame, raw, point, rel, relPoint, posX, posY)
    if raw then
        frame:SetPoint(point, rel, relPoint, posX, posY)
    else
        Pix.Point(frame, point, rel, relPoint, posX, posY)
    end
end

-- Places member i off prev, the outer frame of member j (the one before it along the
-- chain), s apart, dir the chain's direction: the member's own height kept (base), at
-- Top and Bottom the two sharing their bottom (top) edge. A plain icon after a row keeps
-- its own spot (no aspect host). The Crowd Control row then chains off its lockout icon,
-- sp apart, in the same direction.
local function ChainPlaceAfter(backing, place, i, jdx, previous, s, direction, sp)
    local leadSlot, c = Chain.lead[i], Chain.trail[i]
    local raw = Chain.row[i] or leadSlot ~= c
    if Chain.row[jdx] and not backing.coreHost and (leadSlot ~= c or not Chain.row[i]) then
        ChainPlaceOwn(backing, place, i)
        return
    end
    local dy = Chain.base[i] - Chain.base[jdx]
    leadSlot:ClearAllPoints()
    if direction == "up" then
        local edgeSide = (place == "topleft") and "LEFT" or "RIGHT"
        ChainPoint(leadSlot, raw, "BOTTOM" .. edgeSide, previous, "TOP" .. edgeSide, 0, s)
    elseif place == "bottom" then
        if direction == "left" then
            ChainPoint(leadSlot, raw, "TOPRIGHT", previous, "TOPLEFT", -s, 0)
        else
            ChainPoint(leadSlot, raw, "TOPLEFT", previous, "TOPRIGHT", s, 0)
        end
    elseif direction == "left" then
        ChainPoint(leadSlot, raw, "BOTTOMRIGHT", previous, "BOTTOMLEFT", -s, dy)
    else
        ChainPoint(leadSlot, raw, "BOTTOMLEFT", previous, "BOTTOMRIGHT", s, dy)
    end
    if Chain.row[i] and c ~= leadSlot then
        c:ClearAllPoints()
        if direction == "up" then
            local edgeSide = (place == "topleft") and "LEFT" or "RIGHT"
            c:SetPoint("BOTTOM" .. edgeSide, leadSlot, "TOP" .. edgeSide, 0, sp)
        elseif direction == "left" then
            c:SetPoint("BOTTOMRIGHT", leadSlot, "BOTTOMLEFT", -sp, 0)
        else
            c:SetPoint("BOTTOMLEFT", leadSlot, "BOTTOMRIGHT", sp, 0)
        end
    end
end

-- One pass over the plate's shown members of the slot (Chain.busy set: the passes it
-- runs end in ns.NP_CoreChain again).
local function ChainRun(backing, place, k)
    local centred = (place == "top" or place == "bottom")
    local pivot = 1
    if centred then
        for i = 1, k do
            if Chain.row[i] then
                pivot = i
                break
            end
        end
    end
    local s = ChainSpacing(place)
    local sp = mod.GetAuraSpacing("ccs") or 4
    local direction = ChainDir(place)
    ChainPlaceOwn(backing, place, pivot)
    for i = pivot + 1, k do
        ChainPlaceAfter(backing, place, i, i - 1, Chain.trail[i - 1], s, direction, sp)
    end
    if centred then
        -- Leftward from the pivot, whose left edge is its lead (its lockout icon, where the
        -- Crowd Control row is the pivot: the row chains rightward off it).
        for i = pivot - 1, 1, -1 do
            local previous = (i + 1 == pivot) and Chain.lead[i + 1] or Chain.trail[i + 1]
            ChainPlaceAfter(backing, place, i, i + 1, previous, s, "left", sp)
        end
    end
end

function mod.NP_CoreChain(backing, place)
    if Chain.busy or not place or place == "none" then
        return
    end
    local num = ChainMembers(place)
    if num < 2 then
        return
    end
    local k = ChainShown(backing, place, num)
    if k == 0 then
        return
    end
    Chain.busy = true
    local success, err = pcall(ChainRun, backing, place, k)
    Chain.busy = false
    if not success then
        error(err, 0)
    end
    -- A side chain's outermost element is what the target arrows hug.
    if place == "left" or place == "right" then
        mod.PositionArrowsOutsideAuras(backing)
    end
end

-- The cast-lockout icon is hand-built outside AuraKit, so Custom Border on Aura Icons
-- reaches it through its own child frame (the icon inset drops to 0 while that draws);
-- off, the plain 1px edge. Runs on every lockout show, so the restyle is
-- skipped while its inputs (shown state, level, texture, size step, exact px, colour,
-- alpha, offsets, shifts) are unchanged; the child turns off through
-- ApplyBorderStyle(frame, 0) so the UI scale re-apply cannot bring it back.
local function NPLockoutBorder(frame)
    local enabled = mod.GetIconBorderEnabled("ccs")
    local callback = frame._npCB
    if enabled and NPIconCustomBorderOn() then
        if not callback then
            callback = CreateFrame("Frame", nil, frame)
            callback:SetAllPoints(frame)
            callback:EnableMouse(false)
            frame._npCB = callback
        end
        local texture = PVal("customBorderTexture")
        local sz = PVal("customBorderSize") or 1
        local px = CludesUI.BorderPx(PVal("customBorderSizePx"), sz, texture)
        local colour = PVal("customBorderColor")
        local a = PVal("customBorderAlpha") or 1
        local ox, oy = PVal("customBorderOffset"), PVal("customBorderOffsetY")
        local sx, sy = PVal("customBorderShiftX"), PVal("customBorderShiftY")
        -- Above the swipe, as AuraKit seats its aura borders.
        local lvl = frame.cd:GetFrameLevel() + 1
        if
            not callback:IsShown()
            or callback:GetFrameLevel() ~= lvl
            or callback._sTex ~= texture
            or callback._sSz ~= sz
            or callback._sPx ~= px
            or callback._sR ~= colour.r
            or callback._sG ~= colour.g
            or callback._sB ~= colour.b
            or callback._sA ~= a
            or callback._sOX ~= ox
            or callback._sOY ~= oy
            or callback._sSX ~= sx
            or callback._sSY ~= sy
        then
            callback:SetFrameLevel(lvl)
            CludesUI.ApplyBorderStyle(
                callback,
                sz,
                colour.r,
                colour.g,
                colour.b,
                a,
                texture,
                ox,
                oy,
                sx,
                sy,
                "nameplates",
                sz,
                nil,
                px
            )
            local Pix = CludesUI.PP
            if Pix.GetBorders(callback) then
                Pix.CreateBorder(callback, nil, nil, nil, nil, nil, nil, nil, true)
            end
            callback._sTex, callback._sSz, callback._sPx = texture, sz, px
            callback._sR, callback._sG, callback._sB, callback._sA = colour.r, colour.g, colour.b, a
            callback._sOX, callback._sOY, callback._sSX, callback._sSY = ox, oy, sx, sy
        end
        if not frame._npCBInset0 then
            frame._npCBInset0 = true
            frame.icon:ClearAllPoints()
            frame.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
            frame.icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        end
        mod.ApplyFrameIconBorder(frame, false)
        return
    end
    if callback and callback:IsShown() then
        CludesUI.ApplyBorderStyle(callback, 0)
        callback:Hide()
    end
    if frame._npCBInset0 then
        -- Back to the creation inset (0 under the stock styles, else 1).
        frame._npCBInset0 = nil
        local px = mod.NP_Blizz() and 0 or 1
        frame.icon:ClearAllPoints()
        frame.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", px, -px)
        frame.icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -px, px)
    end
    mod.ApplyFrameIconBorder(frame, enabled)
end

function mod.NPC_UpdateLockout(backing)
    if not backing then
        return
    end
    local _, _, cs = mod.GetAuraSlots()
    local lockout = (cs and cs ~= "none") and mod.GetActiveCastLockout and mod.GetActiveCastLockout(backing)
    local frame = backing.npcLockout
    if lockout and backing.health then
        if not frame then
            -- Born in the plate's aspect holder like the slot icons (PlatePool, coreHost),
            -- so a Core Positions chain can hang it off an aura row.
            frame = CreateFrame("Frame", nil, backing.coreHost or backing)
            frame:SetFrameStrata("MEDIUM")
            frame:SetFrameLevel(800)
            frame.icon = frame:CreateTexture(nil, "ARTWORK")
            -- Stock styles: no border, so the icon fills the cell; Blizzard
            -- Style also takes the stock rounded swipe under its ring (the
            -- classic square icon keeps the default swipe).
            local px = mod.NP_Blizz() and 0 or 1
            frame.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", px, -px)
            frame.icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -px, px)
            frame.cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
            frame.cd:SetAllPoints(frame)
            frame.cd:SetReverse(true)
            frame.cd:SetDrawEdge(false)
            local kit = AK or CludesUI.AuraKit
            local swipe = px == 0 and not mod.NP_Classic() and kit and kit.BLIZZ_ROUND_SWIPE
            if swipe and frame.cd.SetSwipeTexture then
                frame.cd:SetSwipeTexture(swipe)
            end
            -- scaleGuard: a plate child, as every Basic nameplate border
            CludesUI.PP.CreateBorder(frame, 0, 0, 0, 1, 1, nil, nil, true)
            NPLockoutBorder(frame)
            backing.npcLockout = frame
        end
        local px = NPSize("cc")
        local height, isCropped = NPHeight("cc", px)
        frame:SetSize(px, height)
        local blizz = mod.NP_Blizz()
        local tc = CropCoords(isCropped, blizz and 0 or nil)
        frame.icon:SetTexture(lockout.icon)
        frame.icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
        frame.cd:SetCooldown(lockout.start, lockout.duration)
        -- Blizzard Style: the stock rounded mask and ring, sized with the cell.
        -- Classic WoW UI: the stock debuff border round the square icon.
        if blizz then
            if mod.NP_Classic() then
                if mod.NP_ApplyClassicIconArt then
                    mod.NP_ApplyClassicIconArt(frame, px, height)
                end
            elseif mod.NP_ApplyBlizzIconArt then
                mod.NP_ApplyBlizzIconArt(frame, frame.icon, px, height)
            end
        end
        PositionLockout(backing, frame, cs)
        NPLockoutBorder(frame)
        frame:Show()
    elseif frame then
        frame:Hide()
    end
    -- Re-anchor the CC container: chains off the lockout while shown.
    local b = isActive[backing]
    if b then
        AnchorNPContainer(b.containers.cc, "cc", backing, cs)
    end
end

-- The target arrows (ns.PositionArrowsOutsideAuras) hug the outer edge of a side aura row
-- they meet: shown counts are engine-secret, so only the engine knows a row's width (an empty
-- row brings the arrow back to the bar's edge).
-- 68914: AddAuraGroup stamps UntrustedLayoutScriptExecution on the container, and only
-- aspect-bearing objects may anchor to one. Aspects cannot be conferred after creation
-- (SetParent/SetPoint inheritance is deliberately blocked -- a reparent-into-holder
-- attempt hard-errored in the field), so EnsureArrows births the arrows inside a
-- DisableUntrustedLayoutScriptsTemplate holder: they inherit the aspect at creation and
-- anchor to containers and readable frames alike.
-- A row counts only while shown and last placed in this very slot: the buff row hides itself
-- for units you cannot attack but keeps its stale layout, and AnchorNPContainer's
-- _npcSlotVal stamp lags a slot change until the plate is placed again.
local function IsSideRow(b, kindName, slotValue, edgeSide)
    local c = b.containers[kindName]
    return slotValue == edgeSide and c ~= nil and c:IsShown() and c._npcSlotVal == edgeSide
end

-- This plate's aura row on `side` ("left"/"right"): the first shown row in that slot
-- (debuffs, buffs, crowd control), with its slot's Y offset and its icons' height. A side
-- that chains two or more elements answers with the outermost shown one instead (an icon
-- too: its bottom over the bar's bottom and its size), the outermost that meets the span
-- a0..a1 over the bar's bottom when one is given (the target arrows' own).
function mod.NPC_SideRow(backing, edgeSide, a0, a1)
    if not Chain.busy and mod.NP_CoreChained(edgeSide) then
        local k = ChainShown(backing, edgeSide, #Chain.m)
        for i = k, 1, -1 do
            local ident = Chain.id[i]
            local posY = Chain.base[i]
            local hgt = Chain.row[i] and (NPHeight(ident, NPSize(ident))) or Chain.sz[i]
            if not a0 or (posY < a1 and a0 < posY + hgt) then
                return Chain.trail[i], posY, hgt
            end
        end
        return nil
    end
    local b = isActive[backing]
    if not b then
        return nil
    end
    local ds, bs, cs = mod.GetAuraSlots()
    local kindName, auraKey
    if IsSideRow(b, "debuffs", ds, edgeSide) then
        kindName, auraKey = "debuffs", "debuffSlot"
    elseif IsSideRow(b, "buffs", bs, edgeSide) then
        kindName, auraKey = "buffs", "buffSlot"
    elseif IsSideRow(b, "cc", cs, edgeSide) then
        kindName, auraKey = "cc", "ccSlot"
    else
        return nil
    end
    local _, posY = mod.GetAuraSlotOffsets(auraKey)
    return b.containers[kindName], posY or 0, (NPHeight(kindName, NPSize(kindName)))
end

-- Whether the full-size spell icon's push on a side row moved since AnchorNPContainer last
-- placed it (container._npcPush).
local function SidePushMoved(c, kindName, auraKey, backing, edgeSide)
    if not c then
        return false
    end
    local _, yOff = mod.GetAuraSlotOffsets(auraKey)
    return mod.NP_FullIconPush(backing, edgeSide, yOff, yOff + (NPHeight(kindName, NPSize(kindName)))) ~= c._npcPush
end

-- The full-size spell icon shows only during a cast, and a side row it meets steps out past it
-- (AnchorNPContainer, PositionLockout): on every cast show and hide, re-place this plate's
-- rows on the icon's side whose push moved. Called only while the full-size icon is on
-- (RefreshCastIconSideReserve).
function mod.NPC_PlaceSideRows(backing)
    local b = isActive[backing]
    if not b then
        return
    end
    local edgeSide = mod.GetCastIconOnRight() and "right" or "left"
    local ds, bs, cs = mod.GetAuraSlots()
    local c = b.containers
    if ds == edgeSide and SidePushMoved(c.debuffs, "debuffs", "debuffSlot", backing, edgeSide) then
        AnchorNPContainer(c.debuffs, "debuffs", backing, ds)
    end
    if bs == edgeSide and SidePushMoved(c.buffs, "buffs", "buffSlot", backing, edgeSide) then
        AnchorNPContainer(c.buffs, "buffs", backing, bs)
    end
    if cs == edgeSide and SidePushMoved(c.cc, "cc", "ccSlot", backing, edgeSide) then
        local lk = backing.npcLockout
        if lk and lk:IsShown() then
            PositionLockout(backing, lk, cs)
        end
        AnchorNPContainer(c.cc, "cc", backing, cs)
    end
end

------------------------------------------------------------------------------
-- Attach / detach
------------------------------------------------------------------------------

-- Plates that arrive while the pool is empty (login trickle window, or genuine
-- exhaustion) wait here; freshly built or freed bundles service them immediately.
local waiting = setmetatable({}, { __mode = "k" })

local function ServiceWaiting()
    for backing in pairs(waiting) do
        waiting[backing] = nil
        if backing.unit and #pool > 0 then
            mod.NPC_AttachPlate(backing, backing.unit)
        end
        if #pool == 0 then
            return
        end
    end
end

function mod.NPC_AttachPlate(backing, unitToken)
    AK = AK or CludesUI.AuraKit
    if not AK then
        return
    end
    if not unitToken or UnitIsUnit(unitToken, "player") then
        return
    end -- personal plate: no aura rows

    local b = isActive[backing]
    if not b then
        b = table.remove(pool)
        if not b then
            waiting[backing] = true -- serviced when a bundle builds or frees
            -- Grow the pool by one bundle per waiting plate (combat-legal
            -- since 68914). A plate that detaches before service just
            -- leaves its bundle pooled for the next spawn.
            if QueueBundleBuild then
                QueueBundleBuild()
            end
            return
        end
        waiting[backing] = nil
        isActive[backing] = b
    end

    b.holder:SetParent(backing)
    b.holder:ClearAllPoints()
    b.holder:SetPoint("CENTER", backing, "CENTER")
    b.holder:Show()

    local ds, bs, cs = mod.GetAuraSlots()
    if b.containers.buffs then
        b.containers.buffs._npcAttackable = not not UnitCanAttack("player", unitToken)
    end
    -- A plate spawning for the CURRENT target picks up the class-power push right here,
    -- so it must be tracked as the plate to re-anchor when the target changes away.
    if UnitIsUnit(unitToken, "target") then
        lastTargetPlate = backing
    end
    AnchorNPContainer(b.containers.debuffs, "debuffs", backing, ds)
    AnchorNPContainer(b.containers.buffs, "buffs", backing, bs)
    AnchorNPContainer(b.containers.cc, "cc", backing, cs)

    BindContainer(b.containers.debuffs, unitToken, ds)
    BindContainer(b.containers.buffs, unitToken, bs)
    BindContainer(b.containers.cc, unitToken, cs)
    mod.PositionArrowsOutsideAuras(backing)
end

-- True while a built glow spec plays animations: everything but the static
-- Blizzard Pandemic Border and Blizzard Border.
function NPB.Animated(enabled, specInfo)
    if not (enabled and specInfo) then
        return false
    end
    local G = CludesUI.Glows
    return specInfo.style ~= G.PANDEMIC_BORDER and specInfo.style ~= G.STEALABLE_BORDER
end

-- Switches an enabled group off and straight back on: off releases its buttons
-- at once (each clears its aura and stops the animations it plays), on keeps
-- the group live for the next attach. A group already off is left alone.
function NPB.CycleGroup(c, auraKey)
    local success, enabled = pcall(c.IsAuraGroupEnabled, c, auraKey)
    if success and enabled == true and pcall(c.SetAuraGroupEnabled, c, auraKey, false) then
        pcall(c.SetAuraGroupEnabled, c, auraKey, true)
    end
end

-- A pooled bundle's holder is hidden, and a hidden container runs no aura
-- pass: its next parse waits for the next attach, so every button that
-- showed an aura at detach keeps it, and a bound glow on it keeps playing. Released here instead, after the hide (the group switches then
-- register no events), only for the groups whose style draws an animated
-- glow, and only once a host is bound: default (static) plates pay nothing.
-- force: the style pass (NPC_ReloadAll), whose restyle may bind the hosts.
function NPB.ReleaseGlowButtons(b, force)
    if not ((force or NPB.bound) and AK and AK.styles) then
        return
    end
    local st = AK.styles
    local c = b.containers.debuffs
    local s = st["np:debuffs"]
    if c and s and NPB.Animated(s.pandemicGlow, s.pandemicSpec) then
        NPB.CycleGroup(c, "np")
        if c._npfGroups then
            for auraKey in pairs(c._npfGroups) do
                NPB.CycleGroup(c, auraKey)
            end
        end
    end
    c = b.containers.buffs
    if not c then
        return
    end
    s = st["np:buffs"]
    if s and NPB.Animated(s.purgeGlow, s.purgeSpec) then
        NPB.CycleGroup(c, "np")
    end
    s = st["np:buffs2"]
    if c._npbSplit and s and NPB.Animated(s.purgeGlow, s.purgeSpec) then
        NPB.CycleGroup(c, "np2")
    end
end

function mod.NPC_DetachPlate(backing)
    waiting[backing] = nil
    if lastTargetPlate == backing then
        lastTargetPlate = nil
    end
    if backing.npcLockout then
        backing.npcLockout:Hide()
    end
    local b = isActive[backing]
    if not b then
        return
    end
    isActive[backing] = nil
    -- Unbound only: the next attach binds its unit afresh (SetUnit +
    -- UpdateAllAuras). A unit cleared here would change nothing, since the
    -- holder hides next and a hidden container neither listens nor parses.
    for i = 1, #KINDS do
        local c = b.containers[KINDS[i]]
        if c then
            c._npcBoundUnit = nil
        end
    end
    b.holder:Hide()
    NPB.ReleaseGlowButtons(b)
    b.holder:SetParent(UIParent)
    b.holder:ClearAllPoints()
    b.holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", -200, -200)
    pool[#pool + 1] = b
    ServiceWaiting()
end

------------------------------------------------------------------------------
-- Settings reload: style + geometry + config fingerprints (one set,
-- containers share settings globally).
------------------------------------------------------------------------------

local npFP = {}

local PURGE_FP_SPEC = {}
local PAN_FP_SPEC = {}
local function StyleFPFor(kindName, position)
    local px = NPSize(kindName)
    local height = NPHeight(kindName, px)
    -- Text settings feed BuildNPStyle, so every input must flip this
    -- fingerprint or a live change never restyles the engine buttons.
    local kindKey = (kindName == "debuffs" and "debuff") or (kindName == "buffs" and "buff") or "cc"
    local duration = AuraDurCfg(kindKey)
    local stacks = StackCfg()
    local purge = "-"
    if kindName == "buffs" and mod.GetDispelGlow then
        -- Capability and the per-type color toggle both feed BuildNPStyle,
        -- so they have to reach this fingerprint or a talent swap / toggle
        -- never restyles the engine buttons.
        local glow, dispelType = NPB.GroupGlow(position or 1)
        local sp = mod.GetDispelGlowSpec and mod.GetDispelGlowSpec(dispelType, PURGE_FP_SPEC)
        if sp then
            purge = FP(
                position or 1,
                glow,
                sp.style,
                sp.r,
                sp.g,
                sp.b,
                sp.lines,
                sp.thickness,
                sp.speed,
                sp.bg,
                sp.bgR,
                sp.bgG,
                sp.bgB
            )
        end
    end
    -- Pandemic Glow (debuffs): every input of BuildNPStyle's pandemic fields,
    -- a constant "-" while off so a glow edit never restyles default users.
    if kindName == "debuffs" and mod.GetPandemicGlow() then
        local sp = mod.GetPandemicGlowSpec(PAN_FP_SPEC)
        purge = FP(
            "pan",
            sp.style,
            sp.r,
            sp.g,
            sp.b,
            sp.lines,
            sp.thickness,
            sp.speed,
            sp.bg,
            sp.bgR,
            sp.bgG,
            sp.bgB
        )
    end
    local durFP = FP(duration.size, duration.x, duration.y, duration.pos, duration.color.r, duration.color.g, duration.color.b)
    local stkFP = FP(stacks.size, stacks.x, stacks.y, stacks.pos, stacks.color.r, stacks.color.g, stacks.color.b)
    -- Custom Border on Aura Icons: every input of NPCustomIconBorder, folded in only
    -- while it is on (a constant "-" otherwise, so a border edit never restyles default
    -- users' icons): the toggle and Border = Custom (the gate), texture, size step, the
    -- exact-size value, colour, alpha, both offsets and both shifts. Colour and alpha go
    -- in as exact strings, not FP's two-decimal numbers.
    local cbFP = "-"
    if NPIconCustomBorderOn() then
        local colour = PVal("customBorderColor")
        cbFP = FP(
            PVal("customBorderTexture"),
            PVal("customBorderSize"),
            tostring(PVal("customBorderSizePx")),
            tostring(colour.r),
            tostring(colour.g),
            tostring(colour.b),
            tostring(PVal("customBorderAlpha")),
            PVal("customBorderOffset"),
            PVal("customBorderOffsetY"),
            PVal("customBorderShiftX"),
            PVal("customBorderShiftY")
        )
    end
    return FP(
        kindName,
        px,
        height,
        durFP,
        stkFP,
        purge,
        CludesUI.GetFontPath("nameplates") or "",
        -- NOT `fn(kind) or true`: the getter legitimately returns false, and
        -- `false or true` would pin this fingerprint input to a constant so
        -- the toggle never restyles (the ternary-falsy trap).
        (not mod.GetIconBorderEnabled) or mod.GetIconBorderEnabled(kindName),
        cbFP,
        PVal("showAuraTooltips") == true
    )
end

local function GeoFP()
    local ds, bs, cs = mod.GetAuraSlots()
    local dx, dy = mod.GetAuraSlotOffsets("debuffSlot")
    local bx, by = mod.GetAuraSlotOffsets("buffSlot")
    local cx, cy = mod.GetAuraSlotOffsets("ccSlot")
    return FP(
        ds,
        bs,
        cs,
        dx,
        dy,
        bx,
        by,
        cx,
        cy,
        NPSize("debuffs"),
        NPSize("buffs"),
        NPSize("cc"),
        mod.GetAuraSpacing and mod.GetAuraSpacing("debuffs") or 0,
        mod.GetAuraSpacing and mod.GetAuraSpacing("buffs") or 0,
        mod.GetAuraSpacing and mod.GetAuraSpacing("ccs") or 0,
        mod.GetAuraCrop and tostring(mod.GetAuraCrop("debuffs")) or "-",
        mod.GetAuraCrop and tostring(mod.GetAuraCrop("buffs")) or "-",
        mod.GetAuraCrop and tostring(mod.GetAuraCrop("ccs")) or "-",
        mod.GetDebuffYOffset and mod.GetDebuffYOffset() or 0,
        mod.GetSideAuraXOffset and mod.GetSideAuraXOffset() or 0,
        PVal("textSlotTop"),
        PVal("topleftSlotGrowth"),
        PVal("toprightSlotGrowth"),
        -- The corner rows rise above a Top Left / Top Right text (its element, Size, Y
        -- offset and the name Y offset, all in the lift).
        mod.NP_TopCornerLift("topleft"),
        mod.NP_TopCornerLift("topright"),
        -- Raise Strata feeds the (generation-guarded) layout pass, so its
        -- toggles must flip the geometry fingerprint like everything else.
        mod.GetSlotRaiseStrata and mod.GetSlotRaiseStrata(ds) or false,
        mod.GetSlotRaiseStrata and mod.GetSlotRaiseStrata(bs) or false,
        mod.GetSlotRaiseStrata and mod.GetSlotRaiseStrata(cs) or false,
        -- The Core Positions chains (order and spacing per slot) and the other members'
        -- slots: ReanchorActive runs every chain again.
        PVal("topSlotOrder"),
        PVal("rightSlotOrder"),
        PVal("leftSlotOrder"),
        PVal("toprightSlotOrder"),
        PVal("topleftSlotOrder"),
        PVal("bottomSlotOrder"),
        PVal("topSlotElementSpacing"),
        PVal("rightSlotElementSpacing"),
        PVal("leftSlotElementSpacing"),
        PVal("toprightSlotElementSpacing"),
        PVal("topleftSlotElementSpacing"),
        PVal("bottomSlotElementSpacing"),
        PVal("raidMarkerPos"),
        PVal("classificationSlot"),
        PVal("factionSlot"),
        PVal("classificationIncludeFaction"),
        -- The Rare/Quest member's halves decide whether it is a member at all.
        PVal("classificationHideRare") and true or false,
        mod.NP_QuestIconOn(),
        -- The Quest Objective Text's slot: its own key and, while that is unset, the legacy
        -- view (Replace Quest Icon with Objective, the Quest Indicator box and slot).
        PVal("questTextSlot"),
        mod.NP_GetQuestTextSlot()
    )
end

local function CfgFP()
    -- NPB.Split decides how many groups the buff row runs, so it belongs
    -- with the container config rather than with the styles.
    return FP(
        PVal("maxDebuffs"),
        PVal("showAllDebuffs"),
        BuffMode(),
        NPB.Split(),
        PVal("debuffIncludeCC"),
        mod.NPF_FP(),
        PVal("hideBloodPlagueCopies") ~= false,
        NPF_SunderOn(),
        BuffDispelByMe()
    )
end

local function ReanchorActive()
    local ds, bs, cs = mod.GetAuraSlots()
    for backing, b in pairs(isActive) do
        AnchorNPContainer(b.containers.debuffs, "debuffs", backing, ds)
        AnchorNPContainer(b.containers.buffs, "buffs", backing, bs)
        AnchorNPContainer(b.containers.cc, "cc", backing, cs)
        -- Slot settings may have flipped between "none" and displayed;
        -- BindContainer no-ops when the binding already matches.
        if backing.unit then
            BindContainer(b.containers.debuffs, backing.unit, ds)
            BindContainer(b.containers.buffs, backing.unit, bs)
            BindContainer(b.containers.cc, backing.unit, cs)
        end
        mod.PositionArrowsOutsideAuras(backing)
    end
end

-- Rewires freshly-ensured containers on active plates (attackability,
-- purge watch) and re-anchors/binds everything. Debounced: each ensure
-- job calls this at its tail, so one pass covers a burst of builds.
local npEnsurePending = false
local function NpEnsureWireSoon()
    if npEnsurePending then
        return
    end
    npEnsurePending = true
    C_Timer.After(0.05, function()
        npEnsurePending = false
        for backing, b in pairs(isActive) do
            if backing.unit and b.containers.buffs then
                b.containers.buffs._npcAttackable = not not UnitCanAttack("player", backing.unit)
            end
        end
        ReanchorActive()
    end)
end

-- Builds any row containers that a bundle is missing for the CURRENT slot
-- settings (a row enabled after the pool was built). Rows disabled at
-- pool-build time leave their skeleton shell UNCONSUMED in b.shells, so a
-- later enable is a combat-legal group add onto that shell; only a bundle
-- whose shell for the row is already gone holds until regen.
local function QueueBundleEnsure(b)
    if b.npcEnsurePending then
        return
    end
    b.npcEnsurePending = true
    AKWorker:Queue(function()
        local ds, bs, cs = mod.GetAuraSlots()
        -- Combat-legal since 68914: AddBundle* consume a pre-born shell when
        -- one exists and create fresh otherwise, in any combat state.
        local function ensure(kindName, slot, add)
            if not (slot and slot ~= "none") or b.containers[kindName] then
                return
            end
            add(b)
        end
        ensure("debuffs", ds, AddBundleDebuffs)
        ensure("buffs", bs, AddBundleBuffs)
        ensure("cc", cs, AddBundleCC)
        -- Capability split: declare or park the non-Magic glow group on
        -- containers that already existed when the split state changed.
        NPB.Apply(b.containers.buffs)
        -- NPF record groups (Tracked Auras): declare missing variants,
        -- park stale ones, drive the np groups' counts by the configs.
        NPF_EnsureRecords(b)
        NpEnsureWireSoon()
        b.npcEnsurePending = nil
    end, "np:ensure")
end

-- Class mode on an aura glow (Dispel or Pandemic) that takes a color: the style
-- prints hold the palette colour, kept here for the colours-changed hook below
-- NPC_ReloadAll. Any other state clears it, so later colour edits never reload.
function NPB.SnapClassColor()
    local PB = CludesUI.Glows.PANDEMIC_BORDER
    local class = (
        PurgeGlowActive()
        and PVal("dispelGlowColorMode") == "class"
        and mod.GetDispelGlowStyle() ~= PB
    )
        or (
            mod.GetPandemicGlow()
            and PVal("pandemicGlowMode") == "class"
            and mod.GetPandemicGlowStyle() ~= PB
        )
    if class then
        NPB.ccR, NPB.ccG, NPB.ccB = CludesUI.Glows.ResolveColor("class")
    else
        NPB.ccR = nil
    end
end

function mod.NPC_ReloadAll()
    AK = AK or CludesUI.AuraKit
    if not AK then
        return
    end

    -- Conditional-bundle ensure: rows enabled after the pool was built get
    -- their containers on demand (cheap scan: 3 nil-checks per bundle).
    do
        local ds, bs, cs = mod.GetAuraSlots()
        local needD = ds and ds ~= "none"
        local needB = bs and bs ~= "none"
        local needC = cs and cs ~= "none"
        local function scan(b)
            if
                (needD and not b.containers.debuffs)
                or (needB and not b.containers.buffs)
                or (needC and not b.containers.cc)
            then
                QueueBundleEnsure(b)
            end
        end
        for i = 1, #pool do
            scan(pool[i])
        end
        for _, b in pairs(isActive) do
            scan(b)
        end
    end

    local val = StyleFPFor("debuffs")
        .. ";"
        .. StyleFPFor("buffs")
        .. ";"
        .. StyleFPFor("buffs", 2)
        .. ";"
        .. StyleFPFor("cc")
    NPB.SnapClassColor()
    if npFP.style ~= val then
        npFP.style = val
        for i = 1, #KINDS do
            local kindName = KINDS[i]
            AK.styles["np:" .. kindName] = BuildNPStyle(kindName)
            AK.RestyleSoon("np:" .. kindName)
        end
        -- The buffs row's style twins restyle in lockstep: the non-Magic
        -- glow half and the plain (non-glow) remainder.
        AK.styles["np:buffs2"] = BuildNPStyle("buffs", 2)
        AK.RestyleSoon("np:buffs2")
        AK.styles["np:buffsplain"] = BuildNPStyle("buffs", "plain")
        AK.RestyleSoon("np:buffsplain")
        -- A bundle pooled while its glow was static (or off) kept the auras
        -- it showed; release those buttons before the restyle above hands
        -- them an animated glow, or it would play on the pooled bundle.
        for i = 1, #pool do
            NPB.ReleaseGlowButtons(pool[i], true)
        end
    end

    val = CfgFP()
    if npFP.cfg ~= val then
        npFP.cfg = val
        local maxDbf = PVal("maxDebuffs") or 5
        local sort = DebuffSort()
        local dbfCand = DebuffCand()
        -- Empty table (not nil) when nothing narrows: guarantees the setter
        -- REPLACES the stored filter rather than risking a nil no-op. While
        -- split, group "np" narrows to Magic; NPB.Apply owns group "np2".
        local buffSplit = NPB.Split()
        local buffCand = (buffSplit and NPB.MAGIC) or BuffCand() or {}
        local buffFilter = AK.Filter(unpack(BuffFilterGlow()))
        local plainToks = BuffFilterPlain()
        local buffFilterPlain = plainToks and AK.Filter(unpack(plainToks)) or nil
        local function apply(b)
            -- Conditional bundles: a row's container may not exist.
            if b.containers.debuffs then
                -- np COUNT is owned by NPF_ApplyContainer now (Show All
                -- flag); the cand re-drive stays -- it wipes any stale
                -- narrowing left by pre-filter-feature sessions.
                b.containers.debuffs:SetAuraGroupCandidateFilters("np", dbfCand)
                -- Enum values can be 0: compare against nil, and the direct
                -- setter (unlike AddAuraGroup) requires an explicit direction.
                if sort ~= nil and SORT_DIR ~= nil then
                    b.containers.debuffs:SetAuraGroupSortMethod("np", sort, SORT_DIR)
                end
            end
            if b.containers.buffs then
                b.containers.buffs:SetAuraGroupCandidateFilters("np", buffCand)
                -- The Enemy Buff Filter mode swaps filter-string tokens, so a
                -- flip has to re-drive BOTH group strings (the setter no-ops
                -- when unchanged) and park/unpark the plain remainder group.
                if b.containers.buffs.SetAuraGroupFilterString then
                    b.containers.buffs:SetAuraGroupFilterString("np", buffFilter)
                    if b.containers.buffs._npbSplit then
                        b.containers.buffs:SetAuraGroupFilterString("np2", buffFilter)
                    end
                    if buffFilterPlain then
                        b.containers.buffs:SetAuraGroupFilterString("npnb", buffFilterPlain)
                    end
                end
                if b.containers.buffs.SetAuraGroupMaxFrameCount then
                    CludesUI.AuraKit.SetGroupCap(b.containers.buffs, "npnb", buffFilterPlain and 4 or 0)
                end
            end
            -- NPF record groups + np counts: declares run on the queued,
            -- budgeted ensure path (npcEnsurePending dedupes).
            QueueBundleEnsure(b)
        end
        for _, b in pairs(isActive) do
            apply(b)
        end
        for i = 1, #pool do
            apply(pool[i])
        end
    end

    val = GeoFP()
    if npFP.geo ~= val then
        npFP.geo = val
        -- Invalidate every bundle's layout stamp (pooled ones re-drive at
        -- their next attach; active ones right now).
        geoGen = geoGen + 1
        ReanchorActive()
    end
    -- Cast-lockout is a hand-built CC icon, not an AuraKit style, so it
    -- has to pick up Show Border (and the custom icon border) here rather
    -- than through RestyleSoon.
    for backing in pairs(isActive) do
        if backing.npcLockout then
            NPLockoutBorder(backing.npcLockout)
        end
    end
end

-- Colors page edits (swatches, darken, resets, profile switches) all end in
-- ApplyColorsToOUF. Once a Class-mode aura glow was printed, a changed class
-- colour re-runs the reload; the glow prints carry the colour, so only the
-- glow styles restyle. Calls in one frame (a profile switch can make two)
-- collapse into one check on the next frame: the flush frame stays hidden
-- until a call and hides itself before working.
do
    local flush = CreateFrame("Frame")
    flush:Hide()
    flush:SetScript("OnUpdate", function(self)
        self:Hide()
        local r0 = NPB.ccR
        if r0 == nil then
            return
        end
        local red, green, blue = CludesUI.Glows.ResolveColor("class")
        if red ~= r0 or green ~= NPB.ccG or blue ~= NPB.ccB then
            mod.NPC_ReloadAll()
        end
    end)
    hooksecurefunc(CludesUI, "ApplyColorsToOUF", function()
        if NPB.ccR ~= nil then
            flush:Show()
        end
    end)
end

------------------------------------------------------------------------------
-- Pool build at login (containers must be created out of combat).
------------------------------------------------------------------------------

-- Pool builds INCREMENTALLY through the shared AuraKit build scheduler: a
-- full synchronous build is ~1200 aura buttons (40 bundles x 3 containers
-- x 10-button batches) and measurably extends the loading screen; even a
-- bundle-per-frame trickle spiked frames. One job per CONTAINER keeps each
-- build step ~4-6ms inside the scheduler's frame budget (combat-paused;
-- never ticks during loading screens). Plates that attach before the pool
-- catches up wait in `waiting` and are serviced as bundles complete.
local built = 0
-- CONDITIONAL bundles: each row's container (a 10-button batch for debuffs/buffs,
-- 2-batch for cc) only builds when its aura slot is actually displayed -- rows set to
-- "none" cost zero frames across the whole pool. Enabling a row later builds the
-- missing containers through the ensure pass in NPC_ReloadAll.
function QueueBundleBuild() -- forward-declared local (pool growth + login build)
    queuedBundles = queuedBundles + 1
    do
        local nb
        -- Fully combat-legal since 68914 (skeleton creation included), so
        -- after an in-combat /reload the whole pool builds WHILE fighting.
        AKWorker:Queue(function()
            nb = table.remove(skeletons)
            if not nb then
                nb = CreateBundleSkeleton()
            end
            local ds = mod.GetAuraSlots()
            if ds and ds ~= "none" then
                AddBundleDebuffs(nb)
            end
        end, "np:debuffs")
        AKWorker:Queue(function()
            if not nb then
                return
            end -- bundle lost to a hard error upstream
            local _, bs = mod.GetAuraSlots()
            if bs and bs ~= "none" then
                AddBundleBuffs(nb)
            end
        end, "np:buffs")
        -- Two stages under one label: the bundle build and the plate attach must
        -- not share a watchdog attempt (a reconnect mid-pull retried the combined
        -- cost to its third strike). "again" front-requeues, so the attach still
        -- follows its own bundle before any newer work.
        local pooled = false
        AKWorker:Queue(function()
            if not nb then
                return
            end -- bundle lost to a hard error upstream
            if not pooled then
                local _, _, cs = mod.GetAuraSlots()
                if cs and cs ~= "none" then
                    AddBundleCC(nb)
                end
                -- NPF record groups apply at BUILD: growth bundles (pre-warm,
                -- attach growth) never see the one-shot reload or a config-FP
                -- flip, and without this their np group renders unfiltered.
                NPF_EnsureRecords(nb)
                -- Mark before the insert: a watchdog between the two loses one
                -- bundle (growth rebuilds it) rather than pooling it twice.
                pooled = true
                pool[#pool + 1] = nb
                built = built + 1
                return "again"
            end
            ServiceWaiting()
            if built == POOL_SIZE then
                mod.NPC_ReloadAll()
            end
        end, "np:cc+pool")
    end
end

local function QueuePoolBuild()
    for i = 1, POOL_SIZE do
        QueueBundleBuild()
    end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:RegisterEvent("PLAYER_TARGET_CHANGED")
boot:SetScript("OnEvent", function(self, evt)
    if evt == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        AK = AK or CludesUI.AuraKit
        if not AK then
            return
        end
        if AuraContainerSortMethod then
            SORT_IMPORTANT = AuraContainerSortMethod.ImportantOnly
            SORT_DEFAULT = AuraContainerSortMethod.Default
        end
        if AuraContainerSortDirection then
            SORT_DIR = AuraContainerSortDirection.Normal
        end
        for i = 1, #KINDS do
            AK.styles["np:" .. KINDS[i]] = BuildNPStyle(KINDS[i])
        end
        AK.styles["np:buffs2"] = BuildNPStyle("buffs", 2)
        AK.styles["np:buffsplain"] = BuildNPStyle("buffs", "plain")
        -- No skeleton pre-birth: creation is combat-legal since 68914, so pool jobs
        -- birth their skeletons inline whenever they run. Plates that spawn before the
        -- first bundles land wait in `waiting` and are serviced as bundles complete.
        QueuePoolBuild()
    elseif evt == "PLAYER_ENTERING_WORLD" then
        -- Capability-split restriction edge: NPB.Split reads AurasRestricted,
        -- which flips on zone edges -- a changed answer re-drives the split
        -- (CfgFP carries it) and the affected styles.
        local nowRestricted = (AK and AK.AurasRestricted and AK.AurasRestricted()) and true or false
        if NPB.lastRestricted ~= nowRestricted then
            NPB.lastRestricted = nowRestricted
            if mod.NPC_ReloadAll then
                mod.NPC_ReloadAll()
            end
        end
        -- Content-aware pre-warm (idempotent: queuedBundles only grows, so
        -- repeated zone-ins are no-ops once the target is met; the pool
        -- never shrinks -- engine frames are never freed anyway). The
        -- zone-in drain rides the login turbo window, not combat frames.
        local _, instanceType = IsInInstance()
        if AK and (instanceType == "party" or instanceType == "raid") then
            for _ = queuedBundles + 1, POOL_TARGET_INSTANCE do
                QueueBundleBuild()
            end
        end
    elseif evt == "PLAYER_TARGET_CHANGED" then
        -- Class power on the target plate pushes top-anchored rows up. Only the
        -- outgoing and incoming target plates can change, so re-anchor exactly those
        -- two -- a full-pool ReanchorActive here re-drove the layout setters on every
        -- plate on every target swap (target churn is constant in combat).
        local ds, bs, cs = mod.GetAuraSlots()
        local previous = lastTargetPlate
        lastTargetPlate = nil
        for backing, b in pairs(isActive) do
            local isNew = backing.unit and UnitIsUnit(backing.unit, "target")
            if isNew then
                lastTargetPlate = backing
            end
            if isNew or backing == previous then
                AnchorNPContainer(b.containers.debuffs, "debuffs", backing, ds)
                AnchorNPContainer(b.containers.buffs, "buffs", backing, bs)
                AnchorNPContainer(b.containers.cc, "cc", backing, cs)
                mod.PositionArrowsOutsideAuras(backing)
            end
        end
    end
end)
