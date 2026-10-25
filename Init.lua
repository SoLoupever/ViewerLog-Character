local addonName, ns = ...

-- Init CharState : événements du jeu → scanners d'état du personnage.
-- Frame propre ; partage uniquement _G.ViewerLogAPI avec le noyau.

local frame = CreateFrame("Frame", "ViewerLog_CharState_EventFrame")

frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_ALIVE")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_LEAVING_WORLD")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("UPDATE_EXHAUSTION")
frame:RegisterEvent("PLAYER_UPDATE_RESTING")
frame:RegisterEvent("PLAYER_XP_UPDATE")
frame:RegisterEvent("TIME_PLAYED_MSG")

-- ── Debounce ScanCharacterMeta ────────────────────────────────────
-- Les events XP/repos arrivent en rafale : un seul appel 0.5s après le dernier.
local _metaTimer = nil
local function ScheduleMetaScan()
    if _metaTimer then _metaTimer:Cancel() end
    _metaTimer = C_Timer.NewTimer(0.5, function()
        _metaTimer = nil
        ns.ScanCharacterMeta()
    end)
end

frame:SetScript("OnEvent", function(self, event, ...)

    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(3, ns.ScanEquipment)
        C_Timer.After(8, ns.ScanCharacterMeta)

    -- Après résurrection.
    elseif event == "PLAYER_ALIVE"
        or event == "PLAYER_EQUIPMENT_CHANGED" then
        ns.ScanEquipment()

    elseif event == "PLAYER_LOGOUT"
        or event == "PLAYER_LEAVING_WORLD" then
        ns.ScanCharacterMeta()
        RequestTimePlayed()

    elseif event == "UPDATE_EXHAUSTION"
        or event == "PLAYER_UPDATE_RESTING"
        or event == "PLAYER_XP_UPDATE" then
        ScheduleMetaScan()

    elseif event == "TIME_PLAYED_MSG" then
        local totalTime = ...
        local charData  = ns.GetCurrentCharData()
        if charData then charData.timePlayed = totalTime end
    end
end)

-- ── Exposition sur l'API partagée ───────────────────────────────
-- Consommée par AltViewerLog (XP reposé).
ns.vl.GetEstimatedRestedPct = ns.GetEstimatedRestedPct
