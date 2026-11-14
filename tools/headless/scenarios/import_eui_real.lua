-- Imports a real older-suite export string (EUI_STRING_FILE) into CludesUI,
-- then exports the imported profile again and compares the two setting by
-- setting (the older suite's names mapped to ours, as the import maps them).
-- Prints what did not carry over. Make the string by loading the older suite in
-- the harness (HARNESS_SUITE=<its folder>) and calling its ExportProfile.
local CUI = rawget(_G, "CludesUI")
local path = assert(os.getenv("EUI_STRING_FILE"), "set EUI_STRING_FILE")
local f = assert(io.open(path, "r"))
local str = f:read("*a"):gsub("%s+$", "")
f:close()

local function Same(a, b, at, out)
    if type(a) ~= type(b) then
        out[#out + 1] = at .. ": " .. type(a) .. " in their string, " .. type(b) .. " after import"
        return
    end
    if type(a) ~= "table" then
        if a ~= b then out[#out + 1] = at .. ": " .. tostring(a) .. " -> " .. tostring(b) end
        return
    end
    for k, v in pairs(a) do Same(v, b[k], at .. "." .. tostring(k), out) end
end

local ok, err = pcall(function()
    local theirs, why = CUI.DecodeImportString(str)
    assert(theirs, "decode refused: " .. tostring(why))
    local sections = 0
    for _ in pairs(theirs.data and theirs.data.addons or {}) do sections = sections + 1 end
    io.write(("real EUI string: %d chars, version %s, %d addon sections, decoded OK\n"):format(#str, tostring(theirs.version), sections))

    -- Applying the profile refreshes live frames, which can stop in code the
    -- fake client cannot run (action button art); the stored settings are
    -- what this checks, so carry on past it.
    local okImport, imported, ierr = pcall(CUI.ImportProfile, str, "Imported")
    io.write("import: ", tostring(okImport and imported), " ", tostring(okImport and (ierr or "") or imported), "\n")

    local again = CUI.ExportProfile("Imported")
    local ours = again and CUI.DecodeImportString(again)
    assert(ours, "could not export the imported profile")
    local diffs = {}
    Same(theirs.data and theirs.data.addons, ours.data and ours.data.addons, "addons", diffs)
    io.write(("settings compared: every addon section; not carried over: %d\n"):format(#diffs))
    for i = 1, math.min(25, #diffs) do io.write("  ", diffs[i], "\n") end
end)
if not ok then io.write("real EUI import: FAILED ", tostring(err), "\n") end
