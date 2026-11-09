--[[
Runs even when NorskenCore can't load: every Norsken addon needs it, so without it they stay silent and this says why.
A [Bootstrap] file of a LoadOnDemand addon runs after the normal addons and before PLAYER_LOGIN, and only hard
dependencies stop it, which is why this TOC lists everything as OptionalDeps. Both options addons carry this file,
the first to get there shows the popup.
]]

local CORE = 'NorskenCore'

-- Core's own strings can't load without Core
local STRINGS = {
    enUS = {
        missing = 'NorskenCore is missing. Install it to use the Norsken addons.',
        disabled = 'NorskenCore is turned off, so the Norsken addons can\'t load.',
        failed = 'NorskenCore couldn\'t load: %s',
        enable = 'Turn on and reload',
    },
    deDE = {
        missing = 'NorskenCore fehlt. Installiere es, um die Norsken-Addons zu nutzen.',
        disabled = 'NorskenCore ist ausgeschaltet, daher können die Norsken-Addons nicht laden.',
        failed = 'NorskenCore konnte nicht laden: %s',
        enable = 'Einschalten und neu laden',
    },
}

local frame = CreateFrame('Frame')
frame:RegisterEvent('PLAYER_LOGIN')
frame:SetScript('OnEvent', function(self)
    self:UnregisterAllEvents()
    if C_AddOns.IsAddOnLoaded(CORE) or _G.NorskenCoreBootstrapShown then return end
    _G.NorskenCoreBootstrapShown = true

    local text = STRINGS[GetLocale()] or STRINGS.enUS
    local _, reason = C_AddOns.IsAddOnLoadable(CORE)
    local dialog = {
        button1 = OKAY,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    if not C_AddOns.DoesAddOnExist(CORE) then
        dialog.text = text.missing
    elseif reason == 'DISABLED' then
        dialog.text = text.disabled
        dialog.button1 = text.enable
        dialog.button2 = CANCEL
        dialog.OnAccept = function()
            C_AddOns.EnableAddOn(CORE)
            C_UI.Reload()
        end
    else
        dialog.text = text.failed:format(_G['ADDON_' .. tostring(reason)] or tostring(reason))
    end

    StaticPopupDialogs.NORSKENCORE_BOOTSTRAP = dialog
    StaticPopup_Show('NORSKENCORE_BOOTSTRAP')
end)
