if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_RaidFrames_PreviewRoles.lua
--
--  Role and class assignment of the 20 preview slots.
--  Reads the earlier preview files through ns and ns._previewInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._previewInternals
-- CUI_RaidFrames_Preview.lua or an earlier preview file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local ipairs = ipairs
local wipe = wipe
local tinsert = table.insert
local UnitName = UnitName
local UnitClass = UnitClass

local RF = mod._internals -- the table of the Raid Frames chain

local previewClassTokens = Inner.previewClassTokens

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of the table that holds its list, which hands the value to
-- every copy: db, PP and containerFrame are the Raid Frames chain's.
local saved
RF.dbSetters[#RF.dbSetters + 1] = function(val)
    saved = val
end

-- Preview role assignments: 2 tanks, 4 healers, 14 DPS.
-- Player (slot 1) uses their real role and counts toward the total.
local previewRoles = {} -- [1..20] = "TANK"/"HEALER"/"DAMAGER"

local function BuildPreviewRoles()
    -- Clear numeric role assignments but preserve random state (underscore keys)
    for i = 1, 20 do
        previewRoles[i] = nil
    end
    wipe(previewClassTokens)

    -- Effective role: the player's spec wins over a stale assigned role
    local playerRole = CludesUI.UnitEffectiveRole("player")
    if playerRole ~= "TANK" and playerRole ~= "HEALER" then
        playerRole = "DAMAGER"
    end
    previewRoles[1] = playerRole
    local _, pct = UnitClass("player")
    previewClassTokens[1] = pct or "WARRIOR"

    -- CUI LEGENDS: slots 2-20 come from the permanent named roster (event
    -- winners + team) -- fixed name/class/role triples instead of the old
    -- round-robin class pools. ns._pvNames rides along through the sort.
    --
    -- The Holy Paladin problem (user design): of the four hpal Legends, TWO
    -- stay Holy Paladins and TWO re-roll to a random non-paladin DPS class
    -- (names kept). Rolled once per preview session -- the pick lives on
    -- previewRoles so it resets exactly with the other random picks.
    if not previewRoles._hpalPick then
        local hpals = {}
        for ri = 1, #mod._PV_ROSTER do
            if mod._PV_ROSTER[ri].hpal then
                hpals[#hpals + 1] = ri
            end
        end
        for i = #hpals, 2, -1 do
            local jdx = math.random(i)
            hpals[i], hpals[jdx] = hpals[jdx], hpals[i]
        end
        local pick = {}
        for key = 3, #hpals do
            local pool = {}
            for _, c in ipairs(mod._PV_DPS_CLASSES) do
                if c ~= "PALADIN" then
                    pool[#pool + 1] = c
                end
            end
            pick[hpals[key]] = pool[math.random(#pool)]
        end
        previewRoles._hpalPick = pick
    end
    mod._pvNames = mod._pvNames or {}
    mod._pvNames[1] = nil -- slot 1 = the player's real name
    for i = 2, 20 do
        local e = mod._PV_ROSTER[i - 1]
        local role, classFile = e.role, e.class
        local reroll = previewRoles._hpalPick[i - 1]
        if reroll then
            role, classFile = "DAMAGER", reroll
        end
        previewRoles[i] = role
        previewClassTokens[i] = classFile
        mod._pvNames[i] = e.name
    end

    -- Sort within each group based on sort settings
    local sortMode = saved.profile.sortMode or "INDEX"
    -- Self ordering pins the player first (or last). Separated mode moves the
    -- player within each preview group; merged mode flows the whole grid in
    -- one sort, which the per-group preview approximates with the player at
    -- the first cell. showSelfFirst here means "self ordering active";
    -- selfLast picks the end.
    local selfLast = saved.profile.showSelfLast
    local showSelfFirst = saved.profile.showSelfFirst or saved.profile.showSelfLast
    -- Same gate as the live headers: FrameSort's list wins only while it is loaded.
    local prioritizeClass = saved.profile.prioritizeClass == true
        and not (sortMode == "FRAMESORT" and mod._FrameSortApi())
    previewRoles._playerSlot = 1 -- default: player is slot 1

    if sortMode == "ROLE" or showSelfFirst or prioritizeClass then
        for g = 0, 3 do
            local baseValue = g * 5
            -- Build sortable list for this group
            local group = {}
            for u = 1, 5 do
                local position = baseValue + u
                group[u] = {
                    role = previewRoles[position],
                    classToken = previewClassTokens[position],
                    name = mod._pvNames and mod._pvNames[position],
                    isPlayer = (position == 1),
                    idx = u,
                }
            end

            if prioritizeClass then
                -- Mirror the live order (the CLASS grouping / ns._BuildRaidClassLists):
                -- role (Sort By = Role) -> class -> name; Self Position below.
                local sortByRole = (sortMode == "ROLE")
                local pName = UnitName("player") or ""
                local rolePri = {}
                for pri, role in ipairs(saved.profile.roleOrder or { "TANK", "HEALER", "DAMAGER" }) do
                    rolePri[role] = pri
                end
                local classPri = {}
                for pri, c in ipairs(saved.profile.classOrder or mod._GetDefaultClassOrder()) do
                    classPri[c] = pri
                end
                table.sort(group, function(a, b)
                    if sortByRole then
                        local ra, rb = rolePri[a.role] or 99, rolePri[b.role] or 99
                        if ra ~= rb then
                            return ra < rb
                        end
                    end
                    local ca, cb = classPri[a.classToken] or 99, classPri[b.classToken] or 99
                    if ca ~= cb then
                        return ca < cb
                    end
                    -- Slot 1 (the player) carries no preview name.
                    local na, nb = a.name or pName, b.name or pName
                    if na ~= nb then
                        return na < nb
                    end
                    return a.idx < b.idx
                end)
            elseif sortMode == "ROLE" then
                local roleOrder = saved.profile.roleOrder or { "TANK", "HEALER", "DAMAGER" }
                local rolePriority = {}
                for pri, role in ipairs(roleOrder) do
                    rolePriority[role] = pri
                end
                -- Stable sort by role priority
                local tmpGroup = {}
                for pri, role in ipairs(roleOrder) do
                    for _, record in ipairs(group) do
                        if record.role == role then
                            tmpGroup[#tmpGroup + 1] = record
                        end
                    end
                end
                -- Any roles not in roleOrder (shouldn't happen, but safe)
                for _, record in ipairs(group) do
                    if not rolePriority[record.role] then
                        tmpGroup[#tmpGroup + 1] = record
                    end
                end
                group = tmpGroup
            end

            if showSelfFirst then
                local playerPos
                for i, record in ipairs(group) do
                    if record.isPlayer then
                        playerPos = i
                        break
                    end
                end
                if playerPos then
                    if selfLast and playerPos < #group then
                        local playerEntry = table.remove(group, playerPos)
                        group[#group + 1] = playerEntry
                    elseif not selfLast and playerPos > 1 then
                        local playerEntry = table.remove(group, playerPos)
                        tinsert(group, 1, playerEntry)
                    end
                end
            end

            -- Write back sorted data
            for u = 1, 5 do
                local position = baseValue + u
                previewRoles[position] = group[u].role
                previewClassTokens[position] = group[u].classToken
                if mod._pvNames then
                    mod._pvNames[position] = group[u].name
                end
                if group[u].isPlayer then
                    previewRoles._playerSlot = position
                end
            end
        end
    end

    -- Random element picks: only randomize once per preview session.
    -- Subsequent calls (from setting changes) reuse the same values.
    if not previewRoles._randomized then
        previewRoles._randomized = true

        -- Pick a random tank for the aggro indicator
        local tanks = {}
        for i = 1, 20 do
            if previewRoles[i] == "TANK" then
                tanks[#tanks + 1] = i
            end
        end
        previewRoles._threatIndex = tanks[math.random(#tanks)] or 1

        -- Pick random players for raid markers: 1 in group 1, 1 in group 4
        previewRoles._markerSlot1 = math.random(5) -- slot 1-5 (group 1)
        previewRoles._markerSlot2 = 15 + math.random(5) -- slot 16-20 (group 4)

        -- Ready check: 3 not ready, 11 ready, 6 pending (randomized)
        local rcStatuses = {}
        for i = 1, 3 do
            rcStatuses[#rcStatuses + 1] = "notready"
        end
        for i = 1, 8 do
            rcStatuses[#rcStatuses + 1] = "ready"
        end
        for i = 1, 6 do
            rcStatuses[#rcStatuses + 1] = "pending"
        end
        rcStatuses[#rcStatuses + 1] = "summon_pending"
        rcStatuses[#rcStatuses + 1] = "summon_accepted"
        rcStatuses[#rcStatuses + 1] = "summon_declined"
        -- Shuffle
        for i = #rcStatuses, 2, -1 do
            local jdx = math.random(i)
            rcStatuses[i], rcStatuses[jdx] = rcStatuses[jdx], rcStatuses[i]
        end
        -- Clear readycheck/summon on marker slots so they don't overlap
        local ms1, ms2 = previewRoles._markerSlot1, previewRoles._markerSlot2
        if ms1 then
            rcStatuses[ms1] = nil
        end
        if ms2 then
            rcStatuses[ms2] = nil
        end
        previewRoles._readyCheck = rcStatuses

        -- Dispel types: one of each in group 1 (slots 1-5)
        local dispelTypes = { "Magic", "Curse", "Disease", "Poison", "" }
        local dispelMap = {}
        for i, dt in ipairs(dispelTypes) do
            dispelMap[i] = dt
        end
        previewRoles._dispelMap = dispelMap

        -- Dead/offline/rez: one of each, random non-player slots. Two of them are
        -- corpses -- a plain dead body and a separate one that's being resurrected --
        -- so the showcase shows both states side by side.
        local statePool = {}
        for i = 2, 20 do
            statePool[#statePool + 1] = i
        end
        for i = #statePool, 2, -1 do
            local jdx = math.random(i)
            statePool[i], statePool[jdx] = statePool[jdx], statePool[i]
        end
        previewRoles._deadSlot = statePool[1] -- plain corpse
        previewRoles._offlineSlot = statePool[2]
        previewRoles._rezSlot = statePool[3] -- corpse with an incoming-rez icon
        -- Plain dead + offline bodies carry no readycheck/summon icon (looks wrong there).
        if rcStatuses[statePool[1]] then
            rcStatuses[statePool[1]] = nil
        end
        if rcStatuses[statePool[2]] then
            rcStatuses[statePool[2]] = nil
        end
        -- The rez corpse gets the incoming-rez icon. But markers win the shared icon
        -- slot (same as the readycheck de-confliction above): if the rez slot landed
        -- on a marker slot, skip the icon (the frame is still shown as a dead body).
        if statePool[3] ~= ms1 and statePool[3] ~= ms2 then
            rcStatuses[statePool[3]] = "rez"
        else
            rcStatuses[statePool[3]] = nil
        end
    end
end

Inner.BuildPreviewRoles, Inner.previewRoles = BuildPreviewRoles, previewRoles
Inner.broken = false
