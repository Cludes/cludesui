if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUICdmBarGlowConditions.lua
--  Extra conditions on a Bar Glow entry, evaluated after the entry's own
--  Glow When result (ns.BarGlowCombine, called from UpdateOverlayVisuals):
--
--    entry.andMode       = "and" | nil (off)
--    entry.conditions[1] = { spellID = n, state = nil (active) | "missing" }
--        The glow also needs a second buff active (or missing). Read from the
--        same active-aura cache the trigger uses (ns._tickBlizzActiveCache:
--        plain booleans, so safe in combat). An "or" is simply a second glow
--        entry on the same button. A second buff not chosen yet changes nothing.
--
--    entry.heroTree      = hero talent subTreeID | nil (any)
--        The glow only runs while that hero tree is active, so one button can
--        carry different glows per hero tree. Ignored on WoW Forever (no hero
--        talents), so a glow imported from retail still lights there.
--
--  Cost: nothing for entries without these keys (two table reads). The hero
--  tree is one C call per hero-gated entry per glow pass, no cache and no
--  events of our own; ns._barGlowAnyHero (set by SetupOverlays) lets the
--  talent-change handler re-run the glow pass only while such an entry exists.
-------------------------------------------------------------------------------
local _, mod = ...

local function ActiveHeroTree()
    local CT = C_ClassTalents
    local ident = CT and CT.GetActiveHeroTalentSpec and CT.GetActiveHeroTalentSpec()
    if type(ident) == "number" and ident > 0 then
        return ident
    end
    return nil
end

-- The current spec's hero trees, for the options dropdown:
-- { { id = subTreeID, name = "Spellslinger" }, ... }
function mod.BarGlowHeroTrees()
    local result = {}
    local CT = C_ClassTalents
    if not (CT and CT.GetHeroTalentSpecsForClassSpec and CT.GetActiveConfigID) then
        return result
    end
    local configID = CT.GetActiveConfigID()
    local success, ids = pcall(CT.GetHeroTalentSpecsForClassSpec, configID)
    if not success or type(ids) ~= "table" then
        return result
    end
    for _, ident in ipairs(ids) do
        local details = configID
            and C_Traits
            and C_Traits.GetSubTreeInfo
            and C_Traits.GetSubTreeInfo(configID, ident)
        result[#result + 1] = { id = ident, name = (details and details.name) or ("Hero Tree " .. ident) }
    end
    return result
end

-- The entry's final glow state, given its own Glow When result `main`.
function mod.BarGlowCombine(record, main, cache)
    local hero = record.heroTree
    if hero and not CludesUI.IS_FOREVER and ActiveHeroTree() ~= hero then
        return false
    end
    if record.andMode ~= "and" then
        return main
    end
    local c = type(record.conditions) == "table" and record.conditions[1]
    local spellRef = type(c) == "table" and tonumber(c.spellID)
    if not spellRef or spellRef <= 0 then
        return main
    end
    local isActive = (cache ~= nil and cache[spellRef] == true)
    local success
    if c.state == "missing" then
        success = not isActive
    else
        success = isActive
    end
    return (main and success) and true or false
end
