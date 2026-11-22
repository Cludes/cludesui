if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_DamageMeters_Format.lua
--
--  Fonts, bar textures, row metrics, number and name formatting, source
--  keys, timer text, class icons and the per-target lists.
--  Reads the earlier Damage Meters files through ns and ns._dmInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._dmInternals
-- CludesUIDamageMeters.lua or an earlier CUI_DamageMeters_*.lua file
-- failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local CUI = CludesUI

local BAR_TEX, DB, _deathStamps = Inner.BAR_TEX, Inner.DB, Inner._deathStamps
local _targetsCache, CleanupFeignCache = Inner._targetsCache, Inner.CleanupFeignCache
local GetCurrentViewDuration = Inner.GetCurrentViewDuration

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._dmInternals, which hands the value to every copy.
local _inCombat = Inner._inCombat
Inner.inCombatSetters[#Inner.inCombatSetters + 1] = function(val) _inCombat = val end
local StartSharedTicker
Inner.startSharedTickerSetters[#Inner.startSharedTickerSetters + 1] = function(val) StartSharedTicker = val end
local _sharedTicker
Inner.sharedTickerSetters[#Inner.sharedTickerSetters + 1] = function(val) _sharedTicker = val end

-- Every meter text (rows, headers, the breakdown tooltip) can show a player's
-- name, so each takes a font family: Cyrillic, Korean and Chinese names draw in
-- the client's own faces where the chosen font has no such letters. Every font
-- write to these strings goes through here (a plain SetFont would pin the face).
local function SetDMFont(fontStr, size, flagsOverride, fontOverride)
    CludesUI.ApplyModuleFontFamily(fontStr, fontOverride, size, "damageMeters", flagsOverride)
end

-- Accent color helper
local function GetAccentRGB()
    local ACC = CUI.CLUDES_GREEN
    if ACC then return ACC.r, ACC.g, ACC.b end
    return CUI.DEFAULT_ACCENT_R or 76 / 255,
        CUI.DEFAULT_ACCENT_G or 201 / 255,
        CUI.DEFAULT_ACCENT_B or 240 / 255
end
-- A header title's "Use Accent" colour: WoW Forever's gold under the variant
-- (its kit carries no CludesUI accent), the accent otherwise.
function mod.DMTitleRGB()
    if mod.DMForever() then
        local color = mod.DM_FV.gold
        return color.r, color.g, color.b
    end
    return GetAccentRGB()
end

-- Bar texture tables
local DM_BAR_TEXTURES, DM_BAR_TEXTURE_NAMES, DM_BAR_TEXTURE_ORDER = CludesUI.BuildBarTextureTables(true)
-- Meter-only extra entry, second in the list: the game's own bar fill (the
-- vanilla status bar), pointed at directly so it needs no SharedMedia
-- registration; Classic WoW UI seeds it.
DM_BAR_TEXTURES["blizzard"] = "Interface\\TargetingFrame\\UI-StatusBar"
DM_BAR_TEXTURE_NAMES["blizzard"] = "Blizzard"
table.insert(DM_BAR_TEXTURE_ORDER, 2, "blizzard")
_G._CUDM_BarTextures = DM_BAR_TEXTURES
_G._CUDM_BarTextureOrder = DM_BAR_TEXTURE_ORDER
_G._CUDM_BarTextureNames = DM_BAR_TEXTURE_NAMES

local function AppendDMSharedMedia()
    if not CUI.AppendSharedMediaTextures then return end
    CUI.AppendSharedMediaTextures(DM_BAR_TEXTURE_NAMES, DM_BAR_TEXTURE_ORDER, nil, DM_BAR_TEXTURES)
end

local function GetBarTexturePath()
    local conf = DB()
    local key = conf and conf.barTexture or "none"
    return CUI.ResolveTexturePath(DM_BAR_TEXTURES, key, BAR_TEX), key
end

local function GetBreakdownBarTexturePath()
    local conf = DB()
    local key = conf and conf.breakdownBarTexture
    if not key or key == "match" then key = conf and conf.barTexture or "none" end
    return CUI.ResolveTexturePath(DM_BAR_TEXTURES, key, BAR_TEX), key
end

-- Thin-line overlay: a hairline bar at the top/bottom edge of a StatusBar. Hooks bar.fill's color/value setters to forward to the overlay when active, instead of touching every call site.
local THIN_LINE_KEYS = { ["thin-line-top"] = "TOP", ["thin-line-bottom"] = "BOTTOM" }
local THIN_LINE_PX = 1

local function SetupThinLine(fillTex, edge)
    if not fillTex._thinLine then
        local tl = CreateFrame("StatusBar", nil, fillTex)
        tl:SetStatusBarTexture(BAR_TEX)
        fillTex._thinLine = tl
        -- Hook SetStatusBarColor to forward to overlay
        local origSSBC = fillTex.SetStatusBarColor
        fillTex.SetStatusBarColor = function(self, red, green, blue, a)
            if self._thinLine and self._thinLineActive then
                self._thinLine:SetStatusBarColor(red, green, blue, a)
                origSSBC(self, 0, 0, 0, 0)
            else
                origSSBC(self, red, green, blue, a)
            end
        end
        -- Hook SetMinMaxValues + SetValue to sync overlay
        local origSMMV = fillTex.SetMinMaxValues
        fillTex.SetMinMaxValues = function(self, lo, hi)
            origSMMV(self, lo, hi)
            if self._thinLine and self._thinLineActive then self._thinLine:SetMinMaxValues(lo, hi) end
        end
        local origSV = fillTex.SetValue
        fillTex.SetValue = function(self, val)
            origSV(self, val)
            if self._thinLine and self._thinLineActive then self._thinLine:SetValue(val) end
        end
    end
    local tl = fillTex._thinLine
    local Pix = CUI and CUI.PP
    local px = THIN_LINE_PX * ((Pix and Pix.mult) or 1)
    tl:ClearAllPoints()
    if edge == "TOP" then
        tl:SetPoint("TOPLEFT", fillTex, "TOPLEFT", 0, 0)
        tl:SetPoint("TOPRIGHT", fillTex, "TOPRIGHT", 0, 0)
    else
        tl:SetPoint("BOTTOMLEFT", fillTex, "BOTTOMLEFT", 0, 0)
        tl:SetPoint("BOTTOMRIGHT", fillTex, "BOTTOMRIGHT", 0, 0)
    end
    tl:SetHeight(px)
    tl:Show()
    fillTex._thinLineActive = true
end

local function ClearThinLine(fillTex)
    if not fillTex._thinLineActive then return end
    fillTex._thinLineActive = false
    if fillTex._thinLine then fillTex._thinLine:Hide() end
    -- Thin-line mode left the fill transparent; reset to opaque so the bar is visible immediately (RefreshUI applies the real color)
    fillTex:SetStatusBarColor(1, 1, 1, 1)
end

local function ApplyBarTexture(fillTex, texPath, texKey)
    -- Blizzard Style: the user's texture as below, plus the stock bevel over
    -- it (strips on the fill, independent of the texture path). Classic WoW
    -- UI bars are plain rectangles: no strips.
    if mod.DMStyle() == "blizzard" then mod.DMApplyBlizzFill(fillTex) end
    local edge = THIN_LINE_KEYS[texKey]
    if edge then
        fillTex:SetStatusBarTexture(BAR_TEX)
        SetupThinLine(fillTex, edge)
    else
        fillTex:SetStatusBarTexture(texPath)
        ClearThinLine(fillTex)
    end
end

-- Physical pixel spacing: convert user values to physical pixels (user setting = physical pixel count).
-- Snapped through PP.Scale so accumulated row offsets (stride * index) don't drift off the pixel
-- grid from float dust -- without this, a spacing of 1 can round to 0px on some rows and 2px on others.
local function PhysicalPixels(userValue)
    local Pix = CUI and CUI.PP
    local mult = (Pix and Pix.mult) or 1
    local value = (userValue or 0) * mult
    if Pix and Pix.Scale then return Pix.Scale(value) end
    return value
end

-- Row geometry with both terms on ONE pixel grid. barHeight and barSpacing are
-- both coordinate units, like the window width and fonts, so bars keep their
-- proportion to the window at any UI scale and a shared profile renders the
-- same relative size for everyone. Both are snapped against the same effective
-- scale: a stride between two grids drifts down the list (-((i-1) * stride)),
-- rendering a spacing of 1 as 0px on some rows and 2px on others.
-- Returns barH, barSp, stride and one physical pixel, in coordinate units.
local function RowMetrics(height, spacingCoord, es)
    local Pix = CUI and CUI.PP
    if Pix and Pix.perfect and Pix.SnapForES then
        if not es or es <= 0 then es = (UIParent and UIParent:GetEffectiveScale()) or 1 end
        local barH = Pix.SnapForES(height or 18, es)
        local barSp = Pix.SnapForES(spacingCoord or 2, es)
        return barH, barSp, barH + barSp, Pix.perfect / es
    end
    local barH, barSp = height or 18, spacingCoord or 2
    return barH, barSp, barH + barSp, (Pix and Pix.mult) or 1
end
-- On ns as well: CreateDMWindow sits at Lua 5.1's 60-upvalue cap, so its call
-- sites reach the helper through ns (already one of its upvalues).
mod._RowMetrics = RowMetrics

-- Number formatting: delegates to the shared CludesUI_NumberFormat.lua engine
-- (breakpoint tables, the CJK wan/yi grouping tables and the
-- AbbreviateNumbers/CreateAbbreviateConfig plumbing all live there now,
-- shared with CludesUIDataBars' gold abbreviation). Values take the profile's
-- Number Format ("meter" value type); Force English Units keeps its K/M/B.
local _forceEnglishUnits = false

-- Re-read the saved setting: once at load (DB not ready yet -> reads false),
-- once after DB creation, and on every options toggle flip.
local function RebuildAbbrevCfg()
    _forceEnglishUnits = false
    if mod.EDM and mod.EDM.DB then
        local saved = mod.EDM.DB()
        if saved and saved.forceEnglishUnits then _forceEnglishUnits = true end
    end
end
RebuildAbbrevCfg()
mod.RebuildNumberFormat = RebuildAbbrevCfg
-- A Number Format change repaints every window; before the DB exists there is
-- nothing to repaint.
CludesUI.RegisterNumberFormatCallback(function()
    if _G._CUDM_DB and mod.RefreshMeter then mod.RefreshMeter() end
end)

local function ShortNumber(num)
    if num == nil then return "0" end
    return CludesUI.AbbreviateNumber(num, _forceEnglishUnits)
end

local function FormatBarValue(amt, perSec, numFmt)
    -- Per-second can drop below 1 on long Overall windows (dumps the raw float); clamp to a min of 1, but only for a plain number -- never compare a secret value (secret sessions are short, so perSec is never sub-1 anyway)
    if perSec ~= nil and (not issecretvalue or not issecretvalue(perSec)) then
        if perSec < 1 then perSec = 1 end
    end
    if numFmt == 0 then return ShortNumber(perSec) end
    if numFmt == 2 and perSec then return format("%s (%s)", ShortNumber(amt), ShortNumber(perSec)) end
    if numFmt == 3 and perSec then return format("%s | %s", ShortNumber(amt), ShortNumber(perSec)) end
    return ShortNumber(amt)
end

-- A combatant's name without its realm. The Name Format (dm.nameFormat, the
-- Left Text cog) then shapes a PLAYER's name: src is the meter row the name
-- belongs to (a player has a class, no creature id and is no Threat list pet;
-- the Pull Aggro line has no class), attacker an Enemy Damage Taken attacker
-- (AggregateEnemyPlayers: a class, neither pet nor mob); with neither, the
-- name is only stripped. Your own row (isLocalPlayer is never secret) always
-- takes your name from your unit, so it reads the same in and out of combat;
-- any other secret name (combat) cannot be split and shows whole. With no
-- Name Format set, src and attacker are never read.
local ShortName = CUI.ShortName
local function StripRealm(name, source, attacker)
    if not name then return "Unknown" end
    if Ambiguate then name = Ambiguate(name, "short") or name end
    local mode = (source or attacker) and DB().nameFormat
    if not mode then return name end
    local player
    if not source then
        local cls = attacker.class
        player = cls ~= nil and cls ~= "" and not attacker.isPet and not attacker.isMob
    else
        local own = source.isLocalPlayer
        if own ~= nil and not issecretvalue(own) and own == true then
            return ShortName(CUI.WithSurname(UnitName("player")), mode) or name
        end
        if issecretvalue(name) then return name end
        local cls = source.classFilename
        player = cls ~= nil and cls ~= "" and source.sourceCreatureID == nil and not source.threatPet
    end
    if not player then return name end
    return ShortName(name, mode)
end

local IsSecret = CUI.IsSecret

-- Is this bar the local player's? isLocalPlayer is documented NeverSecret, so
-- the read is legal mid-combat -- but a doc being wrong must degrade to "not
-- own" (the row stays blocked, today's behavior), never to a thrown compare.
local function IsOwnRow(source)
    local own = source and source.isLocalPlayer
    if own == nil or IsSecret(own) then return false end
    return own == true
end
-- On ns as well: CreateDMWindow sits at Lua 5.1's 60-upvalue cap, so it
-- re-reads both helpers through ns (already one of its upvalues) instead of
-- spending two upvalues of its own.
mod._IsSecret, mod._IsOwnRow = IsSecret, IsOwnRow

-- Resolve a group member's row to a PLAIN guid. Field truth (three debug
-- rounds): in combat the row's `name` and `sourceGUID` are SECRET (the
-- header only renders the name because engine sinks accept secrets) while
-- `classFilename` + `specIconID` are NeverSecret -- and OUT of combat the
-- whole source list reads plain. Group TOKEN reads (UnitGUID/name) stay
-- plain even in combat, but they cannot be JOINED to a row through a secret
-- name. So the bridge is CLASS+SPECICON: out of combat the session's own
-- sources are snapshotted into key "CLASS:specIconID" -> guid (a duplicate
-- key banks FALSE = ambiguous, honest block for e.g. two same-spec
-- players), and the in-combat resolver joins the row's two NeverSecret
-- fields against that snapshot. Guids never change for a player, so
-- pre-combat snapshots stay correct all fight; sources first seen only
-- mid-combat resolve after it ends.
local _srcKeyGuid = {}
-- The group-row resolve channel runs in DUNGEONS ONLY (user rule). Raids
-- mostly ambiguous-block anyway (duplicate specs collapse the class:spec
-- key), while the Overall harvest walk and its session fetch scale with
-- source count; outside instanced parties there is no group audience worth
-- the fetches. Own-row breakdowns and death recaps are separate lanes and
-- keep working everywhere (every caller checks IsOwnRow first).
local function AllyResolveZone()
    local _, instType = IsInInstance()
    return instType == "party"
end
local function SnapshotSourceKeys()
    if not AllyResolveZone() then return end
    -- Declassification LAGS regen (field-confirmed: a post-combat snapshot
    -- banked only the own row): while the Combat addon-restriction is still
    -- active the source list reads partially secret. Skip WITHOUT wiping so
    -- the previous good snapshot survives the lag window; the
    -- ADDON_RESTRICTION_STATE_CHANGED lift edge re-runs this at the exact
    -- declassified moment (the probe reads false during that dispatch by
    -- documented design).
    if
        C_RestrictedActions
        and C_RestrictedActions.IsAddOnRestrictionActive
        and Enum.AddOnRestrictionType
        and C_RestrictedActions.IsAddOnRestrictionActive(Enum.AddOnRestrictionType.Combat)
    then
        return
    end
    -- ADDITIVE, never wiped here: guids are valid for the whole run, and the
    -- Current session ROLLS after each pull -- a refresh against the fresh
    -- (empty) session must not empty the map ("worked once then never
    -- again" was exactly that). The roster branch owns the wipe; Overall is
    -- harvested because it stays populated for the entire run.
    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType) then return end
    local success, s = pcall(
        C_DamageMeter.GetCombatSessionFromType,
        Enum.DamageMeterSessionType.Overall,
        Enum.DamageMeterType.DamageDone
    )
    if not success or not s or not s.combatSources then return end
    for _, source in ipairs(s.combatSources) do
        local g, cls, ic = source.sourceGUID, source.classFilename, source.specIconID
        if
            g
            and cls
            and ic
            and not (IsSecret(g) or IsSecret(cls) or IsSecret(ic))
            and type(cls) == "string"
            and type(ic) == "number"
        then
            local key = cls .. ":" .. ic
            if _srcKeyGuid[key] ~= nil and _srcKeyGuid[key] ~= g then
                _srcKeyGuid[key] = false -- two sources share the key: ambiguous
            else
                _srcKeyGuid[key] = g
            end
        end
    end
end
mod._SnapshotSourceKeys = SnapshotSourceKeys
local function ResolveGroupGUID(source)
    if not source then return nil end
    if not AllyResolveZone() then return nil end
    -- Out of combat the callers' row guids are plain and the gates never
    -- fire, so a resolve call here is a cheap chance to refresh the
    -- snapshot instead (one session fetch at hover edge cadence).
    if not InCombatLockdown() then SnapshotSourceKeys() end
    local cls, ic = source.classFilename, source.specIconID
    if not cls or not ic or IsSecret(cls) or IsSecret(ic) then return nil end
    if type(cls) ~= "string" or type(ic) ~= "number" then return nil end
    local g = _srcKeyGuid[cls .. ":" .. ic]
    if g == false then return nil end
    return g
end
mod._ResolveGroupGUID = ResolveGroupGUID

local function FormatTimer(seconds)
    if not seconds or (issecretvalue and issecretvalue(seconds)) then return "0:00" end
    return format("%d:%02d", math.floor(seconds / 60), math.floor(seconds % 60))
end

-- Deaths row time text. Plain deathTimeSeconds wins; a secret one (in combat)
-- falls back to the placeholder stamped when the row first appeared. Published
-- on ns: CreateDMWindow sits at the 60-upvalue cap and already holds ns.
function mod._DeathTimeText(source, live)
    local t = source.deathTimeSeconds
    if t ~= nil and not (issecretvalue and issecretvalue(t)) then return FormatTimer(t) end
    local rid = source.deathRecapID
    if not rid or (issecretvalue and issecretvalue(rid)) then return "0:00" end
    local st = _deathStamps[rid]
    if not st then
        -- Only the LIVE Current view may stamp: a past segment viewed during
        -- the next pull is secret too, and its deaths must not borrow this
        -- pull's clock.
        if not (_inCombat and live) then return "0:00" end
        st = GetCurrentViewDuration()
        -- 0 = no live duration yet; leave unstamped so a later refresh can.
        if not st or st <= 0 then return "0:00" end
        _deathStamps[rid] = st
    end
    return FormatTimer(st)
end

-- A hidden window never paints, but a Deaths row's in-combat time is stamped on first
-- sight and the feign cache only drops a GUID it sees at 0 HP: a hidden Deaths window
-- keeps both moving without a paint, so it reads right the moment it shows. On ns:
-- CreateDMWindow sits at the 60-upvalue cap.
function mod._DMHiddenDeathsPass(wid)
    if not _inCombat or wid.curDMType ~= Enum.DamageMeterType.Deaths then return end
    CleanupFeignCache()
    -- Only the live Current view stamps (see ns._DeathTimeText)
    if wid.curSessionID or wid.curSession ~= Enum.DamageMeterSessionType.Current then return end
    -- A window switched onto this view while the ticks were off (combat-start auto-Current)
    if not _sharedTicker then StartSharedTicker() end
    local cfg = C_DamageMeter
        and C_DamageMeter.GetCombatSessionFromType
        and C_DamageMeter.GetCombatSessionFromType(
            Enum.DamageMeterSessionType.Current,
            Enum.DamageMeterType.Deaths
        )
    local srcs = cfg and cfg.combatSources
    if not srcs then return end
    for index = 1, #srcs do
        local source = srcs[index]
        local rid, t = source.deathRecapID, source.deathTimeSeconds
        -- A readable death time needs no stamp.
        if
            rid
            and not (issecretvalue and issecretvalue(rid))
            and rid > 0
            and not _deathStamps[rid]
            and (t == nil or (issecretvalue and issecretvalue(t)))
        then
            mod._DeathTimeText(source, true)
        end
    end
end

local function FormatTimerDecimal(seconds)
    if not seconds or (issecretvalue and issecretvalue(seconds)) then return "0:00.0" end
    return format(
        "%d:%02d.%d",
        math.floor(seconds / 60),
        math.floor(seconds % 60),
        math.floor((seconds * 10) % 10)
    )
end

local function GetBreakdownDuration(session, sessionID)
    if sessionID then
        if C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions then
            local sess = C_DamageMeter.GetAvailableCombatSessions()
            if sess then
                for _, s in ipairs(sess) do
                    if
                        s.sessionID == sessionID
                        and type(s.durationSeconds) == "number"
                        and not (issecretvalue and issecretvalue(s.durationSeconds))
                    then
                        return s.durationSeconds
                    end
                end
            end
        end
    elseif session == Enum.DamageMeterSessionType.Current then
        return GetCurrentViewDuration()
    elseif C_DamageMeter and C_DamageMeter.GetSessionDurationSeconds then
        local skinData = C_DamageMeter.GetSessionDurationSeconds(session)
        if type(skinData) == "number" and not (issecretvalue and issecretvalue(skinData)) then
            return skinData
        end
    end
end

local function AmountPerSecond(sum, duration)
    if type(sum) ~= "number" or not duration or duration <= 0 then return nil end
    return sum / duration
end

-- Class icon sprite system
local CLASS_ICON_SPRITE_BASE = "Interface\\AddOns\\CludesUI\\media\\icons\\class-full\\"
local CLASS_ICON_SPRITE_TEX = {}
for _, style in ipairs({ "modern", "dark", "light", "clean", "pixelsComic" }) do
    CLASS_ICON_SPRITE_TEX[style] = CLASS_ICON_SPRITE_BASE .. style .. ".tga"
end
local CLASS_SPRITE_COORDS = CludesUI.CLASS_ICON_SPRITE_COORDS

local ICON_STYLE_VALUES = {
    none = "None",
    spec = "Default Spec Icons",
    blizzard = "Blizzard",
    modern = "Modern",
    pixel = "Pixel",
    pixelsComic = "Comic",
    glyph = "Glyph",
    arcade = "Arcade",
    legend = "Legend",
    midnight = "Midnight",
    runic = "Runic",
}
local ICON_STYLE_ORDER = {
    "none",
    "spec",
    "---",
    "blizzard",
    "modern",
    "pixel",
    "pixelsComic",
    "glyph",
    "arcade",
    "legend",
    "midnight",
    "runic",
}
_G._CUDM_IconStyleValues = ICON_STYLE_VALUES
_G._CUDM_IconStyleOrder = ICON_STYLE_ORDER

local function ZoomedCoords(u1, u2, v1, v2, z)
    local du = (u2 - u1) * z
    local dv = (v2 - v1) * z
    return u1 + du, u2 - du, v1 + dv, v2 - dv
end

local function ResolveIcon(source, iconTex, barH)
    local conf = DB()
    local style = conf.iconStyle or "spec"
    local zoom = conf.classIconZoom or 0.06
    if style == "none" then
        iconTex:Hide()
        return 0
    end

    local class = source.classFilename
    if not class or (issecretvalue and issecretvalue(class)) or class == "" then
        iconTex:Hide()
        return 0
    end

    -- A Threat list's pet row (WoW Forever) shows the pet icon in every style, not its owner's class.
    if source.threatPet and type(source.specIconID) == "number" then
        iconTex:SetTexture(source.specIconID)
        iconTex:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
    elseif style == "spec" then
        -- WoW Forever hides specIconID (always secret since 1.60.1): the class icon below stands in.
        local specIcon = source.specIconID
        if specIcon and not IsSecret(specIcon) and type(specIcon) == "number" and specIcon ~= 0 then
            iconTex:SetTexture(specIcon)
            iconTex:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
            iconTex:SetSize(barH, barH)
            iconTex:SetDesaturated(false)
            iconTex:SetVertexColor(1, 1, 1, 1)
            iconTex:Show()
            return barH
        end
        iconTex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
        if coords then
            iconTex:SetTexCoord(ZoomedCoords(coords[1], coords[2], coords[3], coords[4], zoom))
        else
            iconTex:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        end
    elseif style == "blizzard" then
        iconTex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
        if coords then
            iconTex:SetTexCoord(ZoomedCoords(coords[1], coords[2], coords[3], coords[4], zoom))
        else
            iconTex:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        end
    else
        local coords = CLASS_SPRITE_COORDS[class]
        if coords then
            iconTex:SetTexture(CLASS_ICON_SPRITE_TEX[style] or (CLASS_ICON_SPRITE_BASE .. style .. ".tga"))
            local zoom = conf.spriteIconZoom or 0
            if zoom ~= 0 then
                iconTex:SetTexCoord(ZoomedCoords(coords[1], coords[2], coords[3], coords[4], zoom))
            else
                iconTex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            end
        else
            iconTex:Hide()
            return 0
        end
    end
    iconTex:SetSize(barH, barH)
    iconTex:SetDesaturated(false)
    iconTex:SetVertexColor(1, 1, 1, 1)
    iconTex:Show()
    return barH
end

-- Enemy Damage Taken: one enemy's attackers as rows { name, class, specIcon,
-- total, amountPerSecond, isPet, isMob }, largest first. They are written into
-- the caller's own list `rows`, whose row tables are reused by index, and the
-- call returns rows and their count, or nil. The engine lists one entry per
-- attacker, largest first. Out of combat, entries that share a name are summed
-- and sorted again. Mid-combat the names and amounts are secret, so Lua can
-- neither key a table by them nor add them up: the entries pass through in the
-- engine's order and reach the screen only through the text and bar setters.
-- The class and spec icon never read secret, which keeps the icon and colour.
local _enemyByName = {}
local function AggregateEnemyPlayers(srcData, duration, rowList)
    local spells = srcData and srcData.combatSpells
    local count = spells and #spells or 0
    if count == 0 then return nil end
    local secret = false
    for index = 1, count do
        local spell = spells[index]
        local det = spell.combatSpellDetails
        if IsSecret(spell.totalAmount) or (det and IsSecret(det.unitName)) then
            secret = true
            break
        end
    end
    local num = 0
    for index = 1, count do
        local spell = spells[index]
        local det = spell.combatSpellDetails
        local name = det and det.unitName
        if name ~= nil then
            local p = not secret and _enemyByName[name]
            if p then
                p.total = p.total + (spell.totalAmount or 0)
            else
                num = num + 1
                p = rowList[num]
                if not p then
                    p = {}
                    rowList[num] = p
                end
                local cls, iconTex, pet, mob = det.unitClassFilename, det.specIconID, det.isPet, det.isMob
                p.name = name
                p.class = not IsSecret(cls) and cls or nil
                p.specIcon = not IsSecret(iconTex) and iconTex or nil
                -- The Name Format leaves a pet's or a mob's name whole
                -- (StripRealm); a flag that cannot be read counts as set.
                p.isPet, p.isMob = IsSecret(pet) or pet, IsSecret(mob) or mob
                p.total = spell.totalAmount or 0
                p.amountPerSecond = spell.amountPerSecond
                if not secret then _enemyByName[name] = p end
            end
        end
    end
    wipe(_enemyByName)
    if num == 0 then return nil end
    if not secret then
        for index = 1, num do
            local p = rowList[index]
            p.amountPerSecond = AmountPerSecond(p.total, duration)
        end
        -- Largest first; an insertion sort, since only the first n rows are live.
        for index = 2, num do
            local p, jdx = rowList[index], index - 1
            while jdx >= 1 and rowList[jdx].total < p.total do
                rowList[jdx + 1] = rowList[jdx]
                jdx = jdx - 1
            end
            rowList[jdx + 1] = p
        end
    end
    return rowList, num
end

-- Damage Done targets: cross-reference EnemyDamageTaken to build a complete map of ALL players'
-- damage per enemy in one pass. First hover builds it; later hovers are instant cache lookups. _targetsCache
-- (declared with the event state above) is wiped on DAMAGE_METER_RESET and when combat starts or ends.
local function BuildAllPlayerTargets(session, sessionID)
    local cacheKey = tostring(session) .. "|" .. tostring(sessionID)
    if _targetsCache.key == cacheKey then return _targetsCache.map end

    if not C_DamageMeter then return nil end

    local enemySession
    if sessionID and C_DamageMeter.GetCombatSessionFromID then
        local success, s =
            pcall(C_DamageMeter.GetCombatSessionFromID, sessionID, Enum.DamageMeterType.EnemyDamageTaken)
        if success then enemySession = s end
    elseif C_DamageMeter.GetCombatSessionFromType then
        local success, s =
            pcall(C_DamageMeter.GetCombatSessionFromType, session, Enum.DamageMeterType.EnemyDamageTaken)
        if success then enemySession = s end
    end
    if not enemySession or not enemySession.combatSources or #enemySession.combatSources == 0 then
        _targetsCache.key = cacheKey
        _targetsCache.map = nil

        return nil
    end

    -- Build per-player target totals keyed by unitName; enemy key is creatureID (numeric, never secret) to avoid secret table keys
    local enemyNames = {} -- creatureID -> display name
    local byPlayer = {} -- unitName -> { [creatureID] = totalDamage }
    for ei = 1, #enemySession.combatSources do
        local enemy = enemySession.combatSources[ei]
        local rawCID = enemy.sourceCreatureID
        local eKey = (rawCID and not (issecretvalue and issecretvalue(rawCID))) and rawCID or ei
        enemyNames[eKey] = enemy.name
        local srcData
        if sessionID and C_DamageMeter.GetCombatSessionSourceFromID then
            local success, sd = pcall(
                C_DamageMeter.GetCombatSessionSourceFromID,
                sessionID,
                Enum.DamageMeterType.EnemyDamageTaken,
                enemy.sourceGUID,
                enemy.sourceCreatureID
            )
            if success then srcData = sd end
        elseif C_DamageMeter.GetCombatSessionSourceFromType then
            local success, sd = pcall(
                C_DamageMeter.GetCombatSessionSourceFromType,
                session,
                Enum.DamageMeterType.EnemyDamageTaken,
                enemy.sourceGUID,
                enemy.sourceCreatureID
            )
            if success then srcData = sd end
        end
        if srcData and srcData.combatSpells then
            for _, spell in ipairs(srcData.combatSpells) do
                local det = spell.combatSpellDetails
                if det and det.unitName and not (issecretvalue and issecretvalue(det.unitName)) then
                    local pName = det.unitName
                    local success, amt = pcall(function() return spell.totalAmount end)
                    local amount = (success and amt) or 0
                    if amount > 0 then
                        local pt = byPlayer[pName]
                        if not pt then
                            pt = {}
                            byPlayer[pName] = pt
                        end
                        pt[eKey] = (pt[eKey] or 0) + amount
                    end
                end
            end
        end
    end

    -- Convert each player's enemy map to a sorted array
    local duration = GetBreakdownDuration(session, sessionID)
    local map = {}
    for pName, enemies in pairs(byPlayer) do
        local entries = {}
        for eKey, sum in pairs(enemies) do
            entries[#entries + 1] =
                { name = enemyNames[eKey], total = sum, amountPerSecond = AmountPerSecond(sum, duration) }
        end
        table.sort(entries, function(lhs, rhs) return lhs.total > rhs.total end)
        map[pName] = entries
    end

    _targetsCache.key = cacheKey
    _targetsCache.map = map

    return map
end

local function BuildPlayerTargets(playerName, session, sessionID, maxTargets)
    if not playerName then return nil end
    if issecretvalue and issecretvalue(playerName) then return nil end
    if playerName == "" then return nil end

    local map = BuildAllPlayerTargets(session, sessionID)
    if not map then return nil end

    local entries = map[playerName]
    if not entries or #entries == 0 then return nil end

    if #entries > maxTargets then
        local trimmed = {}
        for index = 1, maxTargets do
            trimmed[index] = entries[index]
        end

        return trimmed
    end

    return entries
end

Inner._srcKeyGuid, Inner.AbbrevNumber = _srcKeyGuid, ShortNumber
Inner.AggregateEnemyPlayers, Inner.AppendDMSharedMedia = AggregateEnemyPlayers, AppendDMSharedMedia
Inner.ApplyBarTexture, Inner.BuildPlayerTargets = ApplyBarTexture, BuildPlayerTargets
Inner.FormatBarValue, Inner.FormatTimer = FormatBarValue, FormatTimer
Inner.FormatTimerDecimal, Inner.GetAccentRGB = FormatTimerDecimal, GetAccentRGB
Inner.GetBarTexturePath = GetBarTexturePath
Inner.GetBreakdownBarTexturePath = GetBreakdownBarTexturePath
Inner.GetBreakdownDuration, Inner.IsOwnRow, Inner.IsSecret = GetBreakdownDuration, IsOwnRow, IsSecret
Inner.PhysicalPixels, Inner.ResolveGroupGUID = PhysicalPixels, ResolveGroupGUID
Inner.ResolveIcon, Inner.SetDMFont, Inner.SnapshotSourceKeys = ResolveIcon, SetDMFont, SnapshotSourceKeys
Inner.StripRealm = StripRealm
Inner.broken = false
