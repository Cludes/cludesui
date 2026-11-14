-- Older-suite (!EUI_) string import, round trip: export this profile, rewrite the
-- payload into the older suite's form (its prefix, its addon and setting
-- names, as their exporter writes them), import that, and check the decoded
-- payload matches what was exported. Prints a summary line; run with
--   HARNESS_PROBE=tools/headless/scenarios/import_eui.lua luajit tools/headless/harness.lua retail
local CUI = rawget(_G, "CludesUI")
local LD = LibStub("LibDeflate")
local S = CUI._Serializer

-- Our names -> theirs (the reverse of the import's renaming).
local function Theirs(v)
    if type(v) == "string" then
        return (v:gsub("CLUDES", "ELLES" .. "MERE"):gsub("Cludes", "Elles" .. "mere"):gsub("cludes", "elles" .. "mere")
            :gsub("%f[%u]CUI", "EUI"):gsub("%f[%a]cui", "eui"))
    end
    if type(v) ~= "table" then return v end
    local out = {}
    for k, val in pairs(v) do out[Theirs(k)] = Theirs(val) end
    return out
end

local function Same(a, b, path, diffs)
    if type(a) ~= type(b) then
        diffs[#diffs + 1] = path .. ": " .. type(a) .. " vs " .. type(b)
        return
    end
    if type(a) ~= "table" then
        if a ~= b then diffs[#diffs + 1] = path .. ": " .. tostring(a) .. " vs " .. tostring(b) end
        return
    end
    for k, v in pairs(a) do Same(v, b[k], path .. "." .. tostring(k), diffs) end
    for k in pairs(b) do if a[k] == nil then diffs[#diffs + 1] = path .. "." .. tostring(k) .. ": missing in export" end end
end

local ok, err = pcall(function()
    local ours = assert(CUI.ExportProfile(CUI.GetActiveProfileName and CUI.GetActiveProfileName() or "Default"), "export failed")
    local original = assert(CUI.DecodeImportString(ours))
    local raw = LD:DecompressDeflate(LD:DecodeForPrint(ours:sub(6)))
    local payload = S.Deserialize(raw)
    local theirsStr = "!E" .. "UI_" .. LD:EncodeForPrint(LD:CompressDeflate(S.Serialize(Theirs(payload))))
    local back, why = CUI.DecodeImportString(theirsStr)
    assert(back, "their string was refused: " .. tostring(why))
    local diffs = {}
    Same(original, back, "payload", diffs)
    local addons = 0
    for _ in pairs(type(back.data) == "table" and type(back.data.addons) == "table" and back.data.addons or {}) do addons = addons + 1 end
    io.write(("import EUI: string %d chars, %d addon sections, differences %d\n"):format(#theirsStr, addons, #diffs))
    for i = 1, math.min(10, #diffs) do io.write("  ", diffs[i], "\n") end
end)
if not ok then io.write("import EUI: FAILED ", tostring(err), "\n") end
