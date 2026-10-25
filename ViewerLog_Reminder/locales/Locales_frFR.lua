local addonName, ns = ...

-- Localisation ViewerLog_Reminder. Table et ns.L propres à la dépendance
-- (même convention que ViewerLog_Guild / ViewerLog_Monnaie).

ns.locales = {}

ns.locales["frFR"] = {
    REMINDER_EVENT_PREFIX = "ViewerLog-Événement",
    REMINDER_EVENT_MSG    = "%s est inscrit à « %s », qui commence dans %s !",

    REMINDER_MAIL_PREFIX  = "ViewerLog-Courrier",
    REMINDER_MAIL_MSG     = "%s a du courrier qui expire dans %s !",

    DURATION_DAYS_HOURS   = "%dj %dh",
    DURATION_HOURS_MIN    = "%dh%02d",
    DURATION_MINUTES      = "%d min",
    DURATION_LESS_MIN     = "moins d'1 min",
}

function ns.L(key)
    local lang = (_G.AltViewerLogDB and _G.AltViewerLogDB.settings
                  and _G.AltViewerLogDB.settings.lang)
                 or GetLocale()
    local t = ns.locales[lang] or ns.locales["frFR"]
    return t[key] or ("[VLR:" .. key .. "]")
end
