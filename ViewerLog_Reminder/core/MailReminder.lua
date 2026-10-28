local addonName, ns = ...

-- Rappel d'expiration du courrier. Ne scanne rien lui-même : le courrier
-- est déjà collecté par ViewerLog (scanner/Mail.lua, boîte ouverte
-- uniquement). Ce module se contente de surveiller charData.mailExpiresAt
-- via ViewerLogAPI.GetMailInfo et d'alerter quand l'échéance approche.
--
-- Isolé : frame et timer propres à ce fichier, aucun appel vers
-- EventReminder.lua ni écriture dans ViewerLogDB (lecture seule).

local SETTING_KEY    = "disableMailReminder"
local LEAD_DAYS      = 7    -- seuil d'alerte avant expiration
local LEAD_SECONDS   = LEAD_DAYS * 86400
local CHECK_INTERVAL = 300  -- 5 min : l'expiration évolue lentement, pas besoin de plus court

local _alertedAt = {}   -- [charKey] = expiresAt déjà signalé (évite le spam ; se redéclenche si nouvelle échéance)

local function CheckMailExpirations()
    local api = _G.ViewerLogAPI
    if not api or not api.IsReady or not api.IsReady() then return end
    if not ns.IsFeatureEnabled(SETTING_KEY) then return end
    if not api.GetMailInfo then return end -- cœur ViewerLog trop ancien, pas cette fonction

    local now = time()
    for _, key in ipairs(api.GetAllCharacters()) do
        local charName, realmName = key:match("^(.+)@(.+)$")
        local info = charName and api.GetMailInfo(charName, realmName)
        if info and info.expiresAt then
            local remaining = info.expiresAt - now
            if remaining > 0 and remaining <= LEAD_SECONDS and _alertedAt[key] ~= info.expiresAt then
                _alertedAt[key] = info.expiresAt
                ns.Print(ns.L("REMINDER_MAIL_PREFIX"), string.format(
                    ns.L("REMINDER_MAIL_MSG"), charName, realmName, ns.FormatDuration(remaining)))
            end
        end
    end
end

local frame = CreateFrame("Frame", "ViewerLog_Reminder_MailFrame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    C_Timer.After(10, CheckMailExpirations)
    C_Timer.NewTicker(CHECK_INTERVAL, CheckMailExpirations)
end)
