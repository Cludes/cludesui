if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Nameplates_Init.lua
--
--  Spec preset login, OnInitialize, OnEnable, the range features and hiding
--  enemy plates out of combat.
--  Reads the earlier nameplate files through ns and ns._npInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._npInternals
-- CludesUINameplates.lua or an earlier nameplate file failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local pairs, ipairs, type = pairs, ipairs, type
local Pix = CludesUI.PP
local UnitCanAttack = UnitCanAttack

local defaultSet, ENP, GetNPOutline, SetFSFont =
    Inner.defaults, Inner.ENP, Inner.GetNPOutline, Inner.SetFSFont
local GetTextSlot, SetupAuraCVars = Inner.GetTextSlot, Inner.SetupAuraCVars
local ApplyClassPowerSetting = Inner.ApplyClassPowerSetting
local RefreshThreatCache, SetProfile = Inner.RefreshThreatCache, Inner.SetProfile
local SetRawSetTex = Inner.SetRawSetTex

local p
Inner.profileSetters[#Inner.profileSetters + 1] = function(val) p = val end

-------------------------------------------------------------------------------
--  SPEC PRESET LOGIN HANDLER
--  Applies the spec-assigned preset on login and spec change, even before the
--  options UI is ever opened. Once the UI opens and RegisterSpecAutoSwitch runs,
--  the framework handler takes over PLAYER_SPECIALIZATION_CHANGED.
-------------------------------------------------------------------------------
do
    -- True when any preset's assigned spec list holds spec id (the store
    -- test for the WoW Forever spec pick below).
    mod.NP_PresetHoldsSpec = function(ident, specMap)
        if not specMap then return false end
        for _, specList in pairs(specMap) do
            if specList[ident] then return true end
        end
        return false
    end

    local function ApplySpecPresetFromDB()
        if not p then return end

        local specIndex = GetSpecialization and GetSpecialization() or 0
        local specID = specIndex and specIndex > 0 and GetSpecializationInfo(specIndex) or nil
        -- WoW Forever: the class counts as each of its retail specs; the first
        -- one in class order that a preset is assigned to picks the preset.
        if CludesUI.IS_FOREVER then
            specID = CludesUI.ForeverClassSpec(nil, mod.NP_PresetHoldsSpec, p._specAssignments)
        end
        if not specID then return end

        local K_ASSIGN = "_specAssignments"
        local K_ACTIVE = "_activePreset"
        local K_DEFAULT = "_specDefaultPreset"
        local K_PRESETS = "_presets"
        local K_SNAP = "_builtinSnapshot"
        local K_CUSTOM = "_customPreset"

        local specMap = p[K_ASSIGN]
        if not specMap then return end

        -- Check if any spec assignment exists at all
        local hasAny = false
        for _, specList in pairs(specMap) do
            if next(specList) then
                hasAny = true
                break
            end
        end
        if not hasAny then return end

        -- Find which preset owns this specID
        local targetKey
        for presetKey, specList in pairs(specMap) do
            if specList[specID] then
                targetKey = presetKey
                break
            end
        end
        -- Fall back to default preset if no direct match
        if not targetKey and p[K_DEFAULT] then targetKey = p[K_DEFAULT] end
        if not targetKey then return end

        local currentActive = p[K_ACTIVE] or "cludesui"
        if currentActive == targetKey then return end -- already correct

        -- Apply the snapshot for targetKey
        local presetKeys = mod._displayPresetKeys -- set below
        if not presetKeys then return end

        if targetKey == "cludesui" then
            for _, key in ipairs(presetKeys) do
                local def = mod.defaults[key]
                if type(def) == "table" and def.r then
                    p[key] = { r = def.r, g = def.g, b = def.b }
                else
                    p[key] = def
                end
            end
            p[K_SNAP] = nil
        elseif targetKey == "custom" then
            if p[K_CUSTOM] then
                for _, key in ipairs(presetKeys) do
                    local val = p[K_CUSTOM][key]
                    if val ~= nil then
                        if type(val) == "table" and val.r then
                            p[key] = { r = val.r, g = val.g, b = val.b }
                        else
                            p[key] = val
                        end
                    end
                end
            end
        elseif targetKey:sub(1, 5) == "user:" then
            local name = targetKey:sub(6)
            local snap = p[K_PRESETS] and p[K_PRESETS][name]
            if snap then
                for _, key in ipairs(presetKeys) do
                    local val = snap[key]
                    if val ~= nil then
                        if type(val) == "table" and val.r then
                            p[key] = { r = val.r, g = val.g, b = val.b }
                        else
                            p[key] = val
                        end
                    end
                end
            end
        end

        p[K_ACTIVE] = targetKey
        p[K_SNAP] = nil
    end

    -- Preset keys for the login handler (set once, never changes). Split into two
    -- tables and concatenated to stay under Lua 5.1's per-function constant limit.
    mod._displayPresetKeys = {
        "showBorder",
        "borderSize",
        "borderColor",
        "castBorderSize",
        "castBorderColor",
        "targetGlowStyle",
        "showTargetArrows",
        "showClassPower",
        "classPowerPos",
        "classPowerYOffset",
        "classPowerXOffset",
        "classPowerScale",
        "classPowerClassColors",
        "classPowerCustomColor",
        "classPowerGap",
        "classPowerShape",
        "classPowerBorder",
        "classPowerBorderColor",
        "classPowerBorderSize",
        "textSlotTop",
        "textSlotRight",
        "textSlotLeft",
        "textSlotCenter",
        "textSlotBottomLeft",
        "textSlotBottomRight",
        "textSlotTopLeft",
        "textSlotTopRight",
        "nameYOffset",
        "healthBarHeight",
        "healthBarWidth",
        "castBarHeight",
    }
    mod._appendDisplayPresetKeys(mod._displayPresetKeys)

    -- Also handle spec changes that happen before the UI is ever opened
    local specLoginFrame = CreateFrame("Frame")
    specLoginFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    specLoginFrame:SetScript("OnEvent", function(_, evt, unitToken)
        if unitToken ~= "player" then return end
        -- Re-read the profile reference: a spec swap may have changed the active
        -- profile, and _C() color lookups would read the old spec's stale data.
        SetProfile(ENP.db.profile)
        RefreshThreatCache()
        -- If the framework handler is registered, let it handle this
        if CludesUI and CludesUI._specSwitchRegistry and #CludesUI._specSwitchRegistry > 0 then return end
        ApplySpecPresetFromDB()
        if mod.RefreshAllSettings then mod.RefreshAllSettings() end
    end)

    -- Expose for calling from OnEnable (login time)
    mod._ApplySpecPresetFromDB = ApplySpecPresetFromDB
    _G._CUNP_RefreshAllSettings = function()
        if mod.RefreshAllSettings then mod.RefreshAllSettings() end
    end
end

local npAddon = ENP
function npAddon:OnInitialize()
    ENP.db = CludesUI.Lite.NewDB("CludesUINameplatesDB", { profile = defaultSet })
    SetProfile(ENP.db.profile)
    mod.db = ENP.db
    -- Non-Target Opacity: derive the cached value at login (no plates exist yet,
    -- so the apply loop no-ops; SetUnit fades new plates as they spawn).
    if mod.NT_RefreshSetting then mod.NT_RefreshSetting() end
    if mod.NP_RefreshTypeScaleSetting then mod.NP_RefreshTypeScaleSetting() end
    -- Append SharedMedia textures to runtime tables so SM texture keys resolve at runtime
    CludesUI.AppendSharedMediaTextures(
        mod.healthBarTextureNames,
        mod.healthBarTextureOrder,
        nil,
        mod.healthBarTextures
    )
end
function npAddon:OnEnable()
    -- Re-read profile: PreSeedSpecProfile may have re-pointed db.profile between OnInitialize and OnEnable.
    SetProfile(ENP.db.profile)
    -- A profile already on a stock style gets its one-time bar texture seed
    -- before the first plate builds (the Style page seeds on the switch);
    -- its own textures go to the CludesUI slot first, so a switch back
    -- restores them.
    if mod.NP_Blizz() then
        if not p.stockBarTextureSeeded and CludesUI.BankEuiStyleSlot then
            CludesUI.BankEuiStyleSlot(p, mod._npStyleSlotKeys)
        end
        mod.NP_SeedStock(p)
    end
    -- The same for the Classic cast colours. An CludesUI slot banked before
    -- they rode the slots gains their current values first, so a switch back
    -- still restores the user's own.
    if mod.NP_Classic() and not p.classicCastSeeded then
        local slots = p._styleSlots
        local cui = type(slots) == "table" and slots.cui
        if type(cui) == "table" then
            local keyList = mod._npClassicCastKeys
            for index = 1, #keyList do
                local k = keyList[index]
                if cui[k] == nil then cui[k] = p[k] end
            end
        elseif CludesUI.BankEuiStyleSlot then
            CludesUI.BankEuiStyleSlot(p, mod._npStyleSlotKeys)
        end
        mod.NP_SeedClassic(p)
    end
    -- WoW Forever: the same for its own seeds (Left Text, the Elite/Rare
    -- Indicator box), the other looks' value of each unseeded key going to
    -- its Forever-only slot first, and the level edges the box follows (armed
    -- only while it shows).
    if mod.NP_Forever() then
        if not (p.foreverLevelSlotSeeded and p.foreverRareSeeded) then
            local cfg = p._foreverStyleSlots
            if type(cfg) ~= "table" then
                cfg = {}
                p._foreverStyleSlots = cfg
            end
            local cui = cfg.cui
            if type(cui) ~= "table" then
                cui = {}
                cfg.cui = cui
            end
            if not p.foreverLevelSlotSeeded then cui.textSlotLeft = p.textSlotLeft end
            if not p.foreverRareSeeded then cui.classificationHideRare = p.classificationHideRare end
            mod.NP_SeedForever(p)
        end
        mod.NP_ForeverWatchLevels()
    end
    SetRawSetTex((Pix and Pix.RawSetTexture) or function(t, val) t:SetTexture(val) end)
    SetupAuraCVars()
    mod.ApplyKeptNameplateCVars()
    ApplyClassPowerSetting()
    -- Apply spec-assigned preset on login (before UI is opened)
    if mod._ApplySpecPresetFromDB then mod._ApplySpecPresetFromDB() end
    -- Text Coloring slot (with Target of Target and the bottom slots), Threat %
    -- and Show Threat Colors flags for the first plates, after the seeds and the
    -- spec preset above rewrote the slots (RefreshAllSettings keeps them after).
    mod.NP_RefreshSlotClassFlags()
    mod.NP_RefreshThreatPctFlag()
    mod.NP_RefreshThreatColorFlag()
    -- PreSeedSpecProfile / the spec preset above may have changed the type scales.
    if mod.NP_RefreshTypeScaleSetting then mod.NP_RefreshTypeScaleSetting() end
    if mod.RangeText_Apply then mod.RangeText_Apply() end
    -- Debuff coloring last: it reads the final profile, and Color Border reads
    -- the plate style, which latches for the session on its first read.
    if mod.DebuffColors_Refresh then mod.DebuffColors_Refresh() end
end

-------------------------------------------------------------------------------
--  Nameplate range features: target distance text plus out-of-range plate alpha.
--  Distance text is a range BUCKET on the target's nameplate -- "15+" =
--  beyond the 15yd rung, inside the next longer one. The API exposes no exact enemy distance;
--  the lower bound comes from the shared range engine's spell ladder (CludesUI_Range.lua),
--  active only while either feature is enabled. Distance-text anchoring: 5px left of whatever
--  text occupies the Right Text core slot, else just outside the health bar's right edge. Zero
--  cost while both are disabled; enabled, one OnUpdate driver ticks 5x/s. Secret range results
--  are skipped -- fail-open to no text or fade, never an error.
-------------------------------------------------------------------------------
do
    -- Single-table state: this file sits at Lua 5.1's 200-local cap, so the whole feature uses ONE chunk local (RT), everything else as table fields.
    local Range = { acc = 0 }

    function Range.Anchor(backing)
        Range.fs:ClearAllPoints()
        local offX = (p and p.rangeTextOffsetX) or 0
        local offY = (p and p.rangeTextOffsetY) or 0
        local rightEl = GetTextSlot("textSlotRight")
        local anchorTo
        if mod.IsNameElement(rightEl) then
            anchorTo = backing.name
        elseif rightEl == "level" then
            anchorTo = backing.levelText
        elseif rightEl == "targetOfTarget" then
            anchorTo = backing.totText
        elseif rightEl == "custom" then
            anchorTo = backing.customRight
        elseif rightEl and rightEl ~= "none" then
            local ca = backing._cachedHealthSlots
            if ca then
                for index = 1, ca._count or 0 do
                    local e = ca[index]
                    if e and e.slotKey == "textSlotRight" and e.fs then
                        anchorTo = e.fs
                        break
                    end
                end
            end
        end
        if anchorTo and anchorTo.IsShown and anchorTo:IsShown() then
            Range.fs:SetPoint("RIGHT", anchorTo, "LEFT", -5 + offX, offY)
        else
            -- WoW Forever: past the level box right of the bar.
            Range.fs:SetPoint(
                "LEFT",
                backing.health or backing,
                "RIGHT",
                5 + offX + mod.NP_ForeverSide(),
                offY
            )
        end
    end

    function Range.Appearance()
        SetFSFont(Range.fs, (p and p.rangeTextSize) or defaultSet.rangeTextSize, GetNPOutline())
        local color = (p and p.rangeTextColor) or defaultSet.rangeTextColor
        Range.fs:SetTextColor(color.r, color.g, color.b, 1)
    end

    function Range.Detach()
        Range.plate = nil
        if Range.carrier then
            Range.carrier:Hide()
            Range.carrier:SetParent(nil)
        end
    end

    function Range.Tick()
        local backing = mod._cachedTargetPlate
        if not backing or not backing.unit or not backing:IsShown() then
            if Range.plate then Range.Detach() end
            return
        end
        if backing ~= Range.plate then
            if not Range.carrier then
                Range.carrier = CreateFrame("Frame")
                Range.carrier:SetSize(2, 2)
                Range.fs = Range.carrier:CreateFontString(nil, "OVERLAY")
            end
            Range.carrier:SetParent(backing)
            Range.carrier:SetPoint("CENTER", backing, "CENTER", 0, 0)
            -- Well above the health bar/text frames: with the Right Text slot occupied the
            -- text sits ON the bar, and a low frame level would draw it underneath the fill.
            Range.carrier:SetFrameLevel(backing:GetFrameLevel() + 30)
            Range.plate = backing
            Range.Appearance()
            Range.Anchor(backing)
            Range.carrier:Show()
        end
        -- "0+" (basically melee) shows nothing: the indicator only matters at distance. Queried
        -- as "target" rather than plate.unit -- this is the target's plate by definition, and
        -- the token lets the shared engine serve the QoL text from one cached walk.
        local lower = CludesUI.Range_LowerBound("target")
        if lower and lower > 0 then
            Range.fs:SetText(lower .. "+")
            Range.fs:Show()
        else
            Range.fs:Hide()
        end
    end

    -- Round-robin BUDGETED sweep: each range verdict is a multi-C-call probe
    -- walk, so classifying every plate every tick is unbounded in crowded
    -- scenes (40 plates x 5Hz x spell+item probes was thousands of C calls
    -- per second). 8 plates per 0.2s tick = full coverage inside ~1s at a
    -- full plate cap, imperceptible for a fade; small scenes still resolve
    -- every tick. Verdicts come from Range_SweepBeyond (per-unit short-TTL
    -- cache; never touches the crosshair/QoL single-slot target caches).
    -- Melee note: at cutoff 5 verdicts rely on the protection-gated item
    -- walk, so in instanced combat the fade can degrade to "no fade" for
    -- melee specs -- deliberate fail-open, never a blocked action.
    function Range.FadeTick()
        local customCutoff = p and p.outOfRangeMode == "custom" and p.outOfRangeCustomRange
        local cutoff = CludesUI.Range_GetAttackCutoff(customCutoff)
        local q = Range.fadeQ
        if not q then
            q = {}
            Range.fadeQ = q
        end
        if not Range.fadeIdx or Range.fadeIdx > #q then
            -- New cycle: snapshot the live plate set (reused table, one wipe
            -- per cycle). Plates that detach mid-cycle are re-checked below.
            wipe(q)
            for _, backing in pairs(mod.plates) do
                q[#q + 1] = backing
            end
            Range.fadeIdx = 1
        end
        local budget = 8
        while Range.fadeIdx <= #q and budget > 0 do
            local backing = q[Range.fadeIdx]
            Range.fadeIdx = Range.fadeIdx + 1
            budget = budget - 1
            local unitToken = backing.unit
            if unitToken and mod.plates[unitToken] == backing then
                local beyond
                -- Cleanly-non-attackable plates (friendly/neutral NPCs) can
                -- never answer an attack-range probe; skip the whole walk.
                -- Only a READABLY-false flag skips -- a secret answer falls
                -- through to the probes, whose own gates fail open.
                local okAtt, att = pcall(UnitCanAttack, "player", unitToken)
                local skip = okAtt and not (issecretvalue and issecretvalue(att)) and att == false
                if not skip then beyond = CludesUI.Range_SweepBeyond(unitToken, cutoff) end
                local alpha = beyond == true and mod._oorAlpha or 1
                if (backing._oorCurAlpha or 1) ~= alpha then
                    backing._oorCurAlpha = alpha
                    mod.NT_Apply(backing)
                end
            end
        end
    end

    function Range.ResetFade()
        -- Drop the round-robin cursor and its plate snapshot too: a disable
        -- mid-cycle must not pin recycled plates in the reused queue.
        if Range.fadeQ then wipe(Range.fadeQ) end
        Range.fadeIdx = nil
        for _, backing in pairs(mod.plates) do
            if backing._oorCurAlpha then
                backing._oorCurAlpha = nil
                mod.NT_Apply(backing)
            end
        end
    end

    -- Options: re-apply font/color/anchor on the live attachment.
    mod.RangeText_Refresh = function()
        if Range.plate and Range.fs then
            Range.Appearance()
            Range.Anchor(Range.plate)
        end
    end

    mod.RangeText_Apply = function()
        local alpha = tonumber(p and p.outOfRangeAlpha) or defaultSet.outOfRangeAlpha
        if alpha < 0 then
            alpha = 0
        elseif alpha > 100 then
            alpha = 100
        end
        mod._oorAlpha = alpha / 100
        local textEnabled = p and p.rangeTextEnabled
        mod._oorFadeEnabled = ((p and p.outOfRangeMode) or defaultSet.outOfRangeMode) ~= "disabled"
            and mod._oorAlpha < 1
        local fadeEnabled = mod._oorFadeEnabled
        if textEnabled or fadeEnabled then
            if not Range.drv then
                Range.drv = CreateFrame("Frame")
                Range.drv:Hide()
                Range.drv:SetScript("OnUpdate", function(_, elapsed)
                    Range.acc = Range.acc + elapsed
                    if Range.acc < 0.2 then return end
                    Range.acc = 0
                    if p and p.rangeTextEnabled then Range.Tick() end
                    if mod._oorFadeEnabled then Range.FadeTick() end
                end)
            end
            -- Ladder builds and invalidation live in the shared range engine.
            CludesUI.Range_SetActive("npRange", true)
            Range.drv:Show()
        else
            CludesUI.Range_SetActive("npRange", false)
            if Range.drv then Range.drv:Hide() end
        end
        if not textEnabled then Range.Detach() end
        if not fadeEnabled then Range.ResetFade() end
    end
end

-------------------------------------------------------------------------------
--  Hide Enemy Nameplates Out of Combat (EXTRAS): drives nameplateShowEnemies,
--  the same CVar behind Blizzard's combat-legal "Show Enemy Name Plates"
--  keybind, so plates flip cleanly at the combat edges. The combat events are
--  registered only while the setting is on (zero cost off); disabling the
--  setting restores plates ON only if this feature ever hid them. All state
--  lives on ns -- this chunk is at the 200-local cap.
-------------------------------------------------------------------------------
mod._oocPlatesCtl = CreateFrame("Frame")
mod.ApplyOOCPlates = function()
    local ctl = mod._oocPlatesCtl
    local enabled = p and p.hideEnemyPlatesOOC == true
    if enabled then
        ctl:RegisterEvent("PLAYER_REGEN_DISABLED")
        ctl:RegisterEvent("PLAYER_REGEN_ENABLED")
        ctl:RegisterEvent("PLAYER_ENTERING_WORLD")
        mod._oocPlatesOwned = true
        -- Read-guarded: RefreshAllSettings calls this on every nameplate settings
        -- change, and a redundant SetCVar broadcasts CVAR_UPDATE to the whole UI.
        local wanted = InCombatLockdown() and "1" or "0"
        if GetCVar("nameplateShowEnemies") ~= wanted then
            CludesUI.SetCVar("nameplateShowEnemies", wanted, "CludesUINameplates")
        end
    else
        ctl:UnregisterEvent("PLAYER_REGEN_DISABLED")
        ctl:UnregisterEvent("PLAYER_REGEN_ENABLED")
        ctl:UnregisterEvent("PLAYER_ENTERING_WORLD")
        if mod._oocPlatesOwned then
            mod._oocPlatesOwned = nil
            CludesUI.SetCVar("nameplateShowEnemies", "1", "CludesUINameplates")
        end
    end
end
mod._oocPlatesCtl:SetScript("OnEvent", function(self, evt)
    if evt == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        mod.ApplyOOCPlates()
        return
    end
    if evt == "PLAYER_REGEN_DISABLED" then
        CludesUI.SetCVar("nameplateShowEnemies", "1", "CludesUINameplates")
    elseif not InCombatLockdown() then
        -- REGEN_ENABLED, or a world entry that lands out of combat.
        CludesUI.SetCVar("nameplateShowEnemies", "0", "CludesUINameplates")
    end
end)
mod._oocPlatesCtl:RegisterEvent("PLAYER_LOGIN")

-------------------------------------------------------------------------------
--  Stacking Speed and Top Screen Inset (General): the client does not save
--  nameplateMotionSpeed or nameplateTopInset, so a game restart puts both back
--  to its default. The sliders keep their value account-wide
--  (CludesUIDB.nameplateKeptCVars; a value at the client's default is not
--  kept) and OnEnable writes it again, only where the CVar differs. Only these
--  two names are ever read from the table. All state lives on ns -- this chunk
--  is at the 200-local cap.
-------------------------------------------------------------------------------
mod._keptCVarNames = { "nameplateMotionSpeed", "nameplateTopInset" }

-- Equal as numbers: the client keeps its own number format.
mod.KeptCVarSame = function(lhs, rhs)
    local posX, posY = tonumber(lhs), tonumber(rhs)
    if posX and posY then return math.abs(posX - posY) < 1e-6 end
    return lhs == rhs
end

-- The sliders' write: sets the CVar, then keeps what the client holds.
mod.KeepNameplateCVar = function(name, value)
    if not CludesUI.SetCVar(name, value, "CludesUINameplates") then return end
    local current = tonumber(GetCVar(name))
    if not (current and CludesUIDB) then return end
    local kept = CludesUIDB.nameplateKeptCVars
    if type(kept) ~= "table" then kept = nil end
    if mod.KeptCVarSame(current, C_CVar.GetCVarDefault(name)) then
        if kept then kept[name] = nil end
        if not (kept and next(kept)) then CludesUIDB.nameplateKeptCVars = nil end
    else
        if not kept then
            kept = {}
            CludesUIDB.nameplateKeptCVars = kept
        end
        kept[name] = current
    end
end

mod.ApplyKeptNameplateCVars = function()
    local kept = CludesUIDB and CludesUIDB.nameplateKeptCVars
    if type(kept) ~= "table" then return end
    if InCombatLockdown() then
        mod.CombatQueue.Defer("NPKeptCVars", mod.ApplyKeptNameplateCVars)
        return
    end
    local nameList = mod._keptCVarNames
    for index = 1, #nameList do
        local name = nameList[index]
        local val = tonumber(kept[name])
        if val and C_CVar.GetCVarInfo(name) and not mod.KeptCVarSame(GetCVar(name), val) then
            CludesUI.SetCVar(name, val, "CludesUINameplates")
        end
    end
end

Inner.broken = false
