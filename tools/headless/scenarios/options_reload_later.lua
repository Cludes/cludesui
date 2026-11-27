-- "Later" on a reload ask (CUI:ShowConfirmPopup): the footer's Reload UI
-- button carries the accent mark until the UI reloads.
local CUI = rawget(_G, "CludesUI")
CUI:Show()
HARNESS_ADVANCE(0.2)
local btn = CUI._footerBar._reloadBtn
local function Marked()
    local n = 0
    for _, region in ipairs({ btn:GetRegions() }) do
        if region:IsShown() and region.GetRotation and region:GetRotation() ~= 0 then n = n + 1 end
    end
    return n > 0
end
OUT:write("== before: marked " .. tostring(Marked()) .. "\n")
local called = false
CUI:ShowConfirmPopup({ title = "Reload Required", message = "x", confirmText = "Reload Now", cancelText = "Later", onCancel = function() called = true end })
HARNESS_ADVANCE(0.1)
local dialog = rawget(_G, "CUIConfirmPopup") or rawget(_G, "CludesUIConfirmPopup")
if dialog and dialog._onCancel then dialog._onCancel() end
OUT:write("== after Later: marked " .. tostring(Marked()) .. ", caller onCancel ran " .. tostring(called) .. "\n")
