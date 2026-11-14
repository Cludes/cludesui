if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_UnlockMode_Filter.lua
--  Unlock Mode element filter: which overlays a typed filter keeps. The box
--  itself is on the toolbar (CUI_UnlockMode_Bar.lua), which calls
--  UM.FilterSet(text) as the text changes and UM.FilterReset() when it hides.
--  Typing hides every overlay whose name lacks one of the typed words; the
--  real frames are never touched. Not saved: hiding the banner clears it.
--  Loaded after CUI_UnlockMode_Session.lua; _unlockCoreInit runs it once with UM.
-------------------------------------------------------------------------------
local _, CUI_NS = ...
CUI_NS = CUI_NS.__cuiCoreNS or CUI_NS  -- standalone builds: the core's own table (CludesUI.lua)
CUI_NS.unlockParts = CUI_NS.unlockParts or {}

-- Filter text -> lower-case words, nil when there are none.
local function ParseFilter(text)
    if type(text) ~= "string" then return nil end
    local words
    for w in text:lower():gmatch("%S+") do
        words = words or {}
        words[#words + 1] = w
    end
    return words
end

local function HasAllWords(words, name)
    if type(name) ~= "string" or name == "" then return false end
    name = name:lower()
    for i = 1, #words do
        if not name:find(words[i], 1, true) then return false end
    end
    return true
end

-- True when the filter keeps an element: no words, or every word (a plain
-- substring, any case) in its label or in the label as shown (translated).
local function FilterKeeps(words, label)
    if not words then return true end
    if HasAllWords(words, label) then return true end
    local shown = CludesUI.L(label)
    return shown ~= label and HasAllWords(words, shown) or false
end

CUI_NS.unlockParts.Filter = function(UM)
local movers, blizzOverlays = UM.movers, UM._blizzOwnedOverlays

local words, lastKey = nil, ""

local function Hides(key)
    return words ~= nil and not FilterKeeps(words, UM.GetBarLabel(key))
end
UM.FilterHides = Hides  -- ghost sync (CUI_UnlockMode_Positions.lua)

-- Mover OnShow hook (CreateMover): every show path ends here.
function UM.FilterOnShow(m)
    if words and Hides(m._barKey) then m:Hide() end
end

-- As the Shift+Right Click hide, without its session flag.
local function HideMover(m)
    m._hoverPending = false
    if UM.selectedMover == m then UM.DeselectMover() end
    if UM.hoveredMover == m then UM.hoveredMover = nil end
    if m._hideOverlayText then m._hideOverlayText() end
    if m._cogBtn then m._cogBtn:Hide() end
    m:Hide()
end

local function Apply()
    if not UM.isUnlocked then return end
    -- A pick mode survives the filter (it helps find the target) unless its own mover hides.
    if UM.pickModeMover and UM.pickMode and Hides(UM.pickModeMover._barKey) then UM.CancelPickMode() end
    if UM.selectElementPicker and Hides(UM.selectElementPicker._barKey) then UM.CancelPickMode() end
    local alpha = UM.darkOverlaysEnabled and 1 or UM.MOVER_ALPHA
    for _, m in pairs(movers) do
        if Hides(m._barKey) then
            if m:IsShown() then HideMover(m) end
        elseif not m:IsShown() and not m._tempHidden then
            m:Sync()
            if m:IsShown() then m:SetAlpha(alpha) end
        end
    end
    for label, ov in pairs(blizzOverlays) do
        if words and not FilterKeeps(words, label) then
            if ov:IsShown() then
                ov._forceCollapse()
                ov:Hide()
                ov._filterHidden = true
            end
        elseif ov._filterHidden then
            ov._filterHidden = nil
            if not ov._tempHidden then ov:SetAlpha(1); ov:Show() end
        end
    end
    -- Ghosts hide themselves in their sync; a refresh brings the kept ones back.
    if CludesUI._RefreshFallbackGhosts then CludesUI._RefreshFallbackGhosts() end
    if CludesUI._RefreshOverrideGhosts then CludesUI._RefreshOverrideGhosts() end
    -- Resting alpha: one hidden during the open fade-in missed its ramp (a running fade resets it).
    if CludesUI._SetFallbackGhostsAlpha then CludesUI._SetFallbackGhostsAlpha(1) end
    if CludesUI._SetOverrideGhostsAlpha then CludesUI._SetOverrideGhostsAlpha(1) end
end

-- The toolbar's box: applies the typed text and says whether a filter is set.
function UM.FilterSet(text)
    local w = ParseFilter(text)
    local key = w and table.concat(w, " ") or ""
    if key ~= lastKey then
        words, lastKey = w, key
        Apply()
    end
    return words ~= nil
end

-- The toolbar hid (Layout Mode closed, or a combat pause): forget the filter.
function UM.FilterReset()
    words, lastKey = nil, ""
    for _, ov in pairs(blizzOverlays) do ov._filterHidden = nil end
end
end
