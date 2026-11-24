-- Options themes (CludesUI.THEME_TINTS, CUI.SetActiveTheme): each theme tints
-- the frame art and the rail fill, and a pick takes its accent even over a
-- saved custom accent; picking an accent afterwards still wins.
local CUI = rawget(_G, "CludesUI")
CUI:Show()
HARNESS_ADVANCE(0.2)
CUI.SetActiveProfileAccent({ r = 1, g = 0, b = 0 }, false)
CUI.RefreshAccent()
local function Hex(r, g, b) return ("%02x%02x%02x"):format(r * 255 + 0.5, g * 255 + 0.5, b * 255 + 0.5) end
local function RailFill()
    for _, kid in ipairs({ CUI._sidebar:GetChildren() }) do
        if kid:GetWidth() == 60 then
            for _, region in ipairs({ kid:GetRegions() }) do
                local fill = region["\0v"] and region["\0v"].ColorTexture
                if fill then -- the first fill made is the rail's background
                    return Hex(fill[1], fill[2], fill[3])
                end
            end
            return "?"
        end
    end
end
local function Report(label)
    local r, g, b = CUI.ResolveActiveAccent()
    -- The art's two layers (they swap on every pick; the new tint is on one).
    local tints = {}
    for _, region in ipairs({ CUI._bgTexture:GetParent():GetRegions() }) do
        local path = region.GetTexture and region:GetTexture()
        if type(path) == "string" and path:find("cui%-bg%-clean%.png") then tints[#tints + 1] = Hex(region:GetVertexColor()) end
    end
    table.sort(tints)
    OUT:write(("== %s: accent %s, rail %s, art tints %s\n"):format(label, Hex(r, g, b), tostring(RailFill()), table.concat(tints, "/")))
end
Report("custom red accent")
for _, name in ipairs(CUI.THEME_ORDER) do
    CUI.SetActiveTheme(name)
    CUI.RefreshAccent()
    HARNESS_ADVANCE(1)
    Report(name)
end
CUI.SetAccentColor(0, 1, 0)
Report("accent picked after theme")
-- The open page's row carries the accent bar.
CUI:SelectModule("CludesUIUnitFrames")
HARNESS_ADVANCE(0.2)
for _, kid in ipairs({ CUI._addonScrollChild:GetChildren() }) do
    if kid._bar and kid:IsShown() then
        OUT:write(("== page row %s bar %s\n"):format(tostring(kid._label:GetText()), tostring(kid._bar:IsShown())))
    end
end
