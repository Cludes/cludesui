-- Info Bar > Spacer block between two others, and a vertical bar.
local H = dofile("tools/headless/scenarios/_common.lua")
H.OUT = OUT
H.Block("clock")
H.b.settings.localTime = false -- server time: the local clock would differ between runs
H.mod.AddBlock(H.bar.id, "spacer")
H.mod.AddBlock(H.bar.id, "spacer")
H.Show("spacer")
H.Vertical("spacer vertical")
