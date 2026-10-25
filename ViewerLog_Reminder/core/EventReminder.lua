local addonName, ns = ...

-- Rappel d'événement du calendrier WoW. Chaque personnage, tant qu'il est
-- connecté, scanne les événements du jour où il est inscrit et les stocke
-- dans son propre charData (via ViewerLogAPI.GetCurrentCharData) — comme
-- Mail.lua le fait déjà pour le courrier. N'importe quel personnage peut
-- ensuite déclencher l'alerte pour n'importe quel autre (lecture croisée
-- via GetAllCharacters/GetCharacterByKey), d'où l'intérêt de préciser le
-- nom du perso concerné dans le message.
--
-- Isolé : frame et timer propres à ce fichier, aucun appel vers
-- MailReminder.lua ni vers le cœur autrement que via ViewerLogAPI.

local SETTING_KEY   = "disableEventReminder"
local LEAD_MINUTES  = 30   -- délai d'alerte avant le début de l'événement
local LEAD_SECONDS  = LEAD_MINUTES * 60
local SCAN_INTERVAL = 30   -- secondes entre deux passages (scan + vérif)

local _alerted = {}   -- [charKey..":"..eventID] = true (remis à zéro à chaque session)

-- Statuts considérés comme "inscrit" (cf. Enum.CalendarStatus). Available/
-- Tentative/Standby/Invited ne sont pas des confirmations fermes → ignorés.
local REGISTERED_STATUS = {
    [Enum.CalendarStatus.Confirmed] = true,
    [Enum.CalendarStatus.Signedup]  = true,
}

-- CalendarTime → epoch. Cohérent tant que "maintenant" (time()) et cette
-- conversion utilisent la même horloge locale (cf. CheckReminders).
local function CalendarTimeToEpoch(t)
    return time({ year = t.year, month = t.month, day = t.monthDay, hour = t.hour, min = t.minute, sec = 0 })
end

-- Certains champs de C_Calendar.GetDayEvent() peuvent être des "secret
-- value" (protection Blizzard). Une secret value ne doit jamais servir de
-- clé de table (`t[secretValue]` plante : "cannot be indexed with secret
-- keys"), ni être comparée/sauvegardée — même principe que le fix
-- targetInfo.lua sur GetNpcName(). On ignore l'événement plutôt que de
-- risquer un crash ou une fuite en SavedVariables.
local function IsEventUsable(ev)
    return not issecretvalue(ev.inviteStatus)
        and not issecretvalue(ev.eventID)
        and not issecretvalue(ev.title)
        and not issecrettable(ev.startTime)
end

-- Scanne les événements du jour pour le perso courant. Réécriture complète
-- de charData.reminderEvents à chaque passage (pas de résidu si un
-- événement est retiré/désinscrit du calendrier).
local function ScanTodayEvents()
    local api = _G.ViewerLogAPI
    local charData = api and api.GetCurrentCharData and api.GetCurrentCharData()
    if not charData then return end

    local today = C_DateAndTime.GetCurrentCalendarTime()
    local numEvents = C_Calendar.GetNumDayEvents(0, today.monthDay) or 0

    local events = {}
    for i = 1, numEvents do
        local ev = C_Calendar.GetDayEvent(0, today.monthDay, i)
        if ev and IsEventUsable(ev) and REGISTERED_STATUS[ev.inviteStatus] then
            events[#events + 1] = {
                id       = ev.eventID,
                title    = ev.title,
                startsAt = CalendarTimeToEpoch(ev.startTime),
            }
        end
    end

    charData.reminderEvents = (#events > 0) and events or nil
end

-- Vérifie TOUS les personnages connus (pas seulement celui en jeu) : un
-- événement scanné hier soir sur un autre perso doit pouvoir alerter
-- aujourd'hui, même si on joue un alt différent.
local function CheckReminders()
    local api = _G.ViewerLogAPI
    if not api or not api.IsReady or not api.IsReady() then return end
    if not ns.IsFeatureEnabled(SETTING_KEY) then return end

    local now = time()
    for _, key in ipairs(api.GetAllCharacters()) do
        local charData = api.GetCharacterByKey(key)
        local events = charData and charData.reminderEvents
        if events then
            local charName = key:match("^(.+)@")
            for _, ev in ipairs(events) do
                local remaining = ev.startsAt - now
                local alertKey = key .. ":" .. tostring(ev.id)
                if remaining > 0 and remaining <= LEAD_SECONDS and not _alerted[alertKey] then
                    _alerted[alertKey] = true
                    ns.Print(ns.L("REMINDER_EVENT_PREFIX"), string.format(
                        ns.L("REMINDER_EVENT_MSG"), charName or key, ev.title, ns.FormatDuration(remaining)))
                end
            end
        end
    end
end

local frame = CreateFrame("Frame", "ViewerLog_Reminder_EventFrame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST")
frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(5, function()
            if ns.IsFeatureEnabled(SETTING_KEY) then
                C_Calendar.OpenCalendar()
            end
        end)
        C_Timer.NewTicker(SCAN_INTERVAL, function()
            if ns.IsFeatureEnabled(SETTING_KEY) then
                C_Calendar.OpenCalendar()
                ScanTodayEvents()
            end
            CheckReminders()
        end)

    elseif event == "CALENDAR_UPDATE_EVENT_LIST" then
        if ns.IsFeatureEnabled(SETTING_KEY) then
            ScanTodayEvents()
        end
    end
end)
