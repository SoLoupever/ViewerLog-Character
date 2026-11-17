local addonName, ns = ...

-- Déclencheurs du scanner. Pas de scan sur PLAYER_ENTERING/LEAVING_WORLD
-- (se redéclenchent à chaque écran de chargement).

local frame = CreateFrame("Frame", "ViewerLog_Reput_EventFrame")

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("UPDATE_FACTION")
frame:RegisterEvent("MAJOR_FACTION_RENOWN_LEVEL_CHANGED")
frame:RegisterEvent("MAJOR_FACTION_UNLOCKED")

frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        C_Timer.After(5, function() ns.ScanReputations(true, true) end)
    elseif event == "PLAYER_LOGOUT" then
        ns.ScanReputations()
    elseif event == "MAJOR_FACTION_UNLOCKED" then
        ns.ScanReputations(true, true)
    else
        ns.ScanReputations(true)
    end
end)

if _G.ViewerLogAPI then
    _G.ViewerLogAPI.ScanReputations = ns.ScanReputations
end
