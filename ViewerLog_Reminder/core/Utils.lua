local addonName, ns = ...

-- Utilitaires partagés par EventReminder.lua et MailReminder.lua.
-- Aucune logique métier ici : juste ce qui évite de dupliquer le
-- formatage/l'impression dans les deux fichiers. Ne dépend de rien
-- d'autre dans cet addon → chargé en premier.

-- Lit un flag "disableXxx" dans ViewerLogDB.settings via ViewerLogAPI
-- (aucun accès direct à ViewerLogDB depuis une dépendance). Flag absent
-- ou cœur ViewerLog trop ancien (pas de GetSetting) → considéré activé.
function ns.IsFeatureEnabled(disableSettingKey)
    local api = _G.ViewerLogAPI
    if not api or not api.IsReady or not api.IsReady() then return false end
    if not api.GetSetting then return true end
    return not api.GetSetting(disableSettingKey)
end

-- Formate une durée en secondes : "2j 3h", "4h05", "12 min", "moins d'1 min".
function ns.FormatDuration(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    local days    = math.floor(seconds / 86400)
    local hours   = math.floor((seconds % 86400) / 3600)
    local minutes = math.floor((seconds % 3600) / 60)

    if days > 0 then
        return string.format(ns.L("DURATION_DAYS_HOURS"), days, hours)
    elseif hours > 0 then
        return string.format(ns.L("DURATION_HOURS_MIN"), hours, minutes)
    elseif minutes > 0 then
        return string.format(ns.L("DURATION_MINUTES"), minutes)
    end
    return ns.L("DURATION_LESS_MIN")
end

-- Impression chat, même habillage couleur que le cœur ViewerLog.
function ns.Print(label, text)
    print(string.format("|cff9955ff[%s]|r %s", label, text))
end
