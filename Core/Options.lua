---@class NRSKNUI
local NRSKNUI = select(2, ...)
local L = NRSKNUI.Libs.AL

local InCombatLockdown = InCombatLockdown
local format = string.format
local strtrim, strlower = strtrim, strlower

local OPTIONS = 'NorskenAuras_Options'
local SHARED_OPTIONS = 'NorskenCore_Options'
local LOAD_ORDER = { SHARED_OPTIONS, OPTIONS }

---The window lives in a LoadOnDemand addon, loaded the first time it's opened.
---@return boolean loaded
local function LoadOptions()
    if C_AddOns.IsAddOnLoaded(OPTIONS) then return true end

    local _, _, _, _, reason = C_AddOns.GetAddOnInfo(OPTIONS)
    if reason == 'MISSING' then
        NRSKNUI:Print(format(L['%s is missing, reinstall NorskenAuras.'], OPTIONS))
        return false
    end

    -- a disabled options folder would leave the command doing nothing, so turn it back on for this character
    local guid = UnitGUID('player')
    C_AddOns.EnableAddOn(SHARED_OPTIONS, guid)
    C_AddOns.EnableAddOn(OPTIONS, guid)

    -- the TOC only lists it as optional (see Bootstrap.lua), which doesn't load a LoadOnDemand addon, so it's loaded first
    for _, name in ipairs(LOAD_ORDER) do
        local loaded, failure = C_AddOns.LoadAddOn(name)
        if not loaded then
            NRSKNUI:Print(name .. ': ' .. (_G['ADDON_' .. tostring(failure)] or tostring(failure)))
            return false
        end
    end

    -- folders from different releases mixed together break in odd ways, so say so up front
    local version = C_AddOns.GetAddOnMetadata(OPTIONS, 'Version')
    local addonVersion = C_AddOns.GetAddOnMetadata('NorskenAuras', 'Version')
    if version ~= addonVersion then
        NRSKNUI:Print(format(L['%s is version %s but NorskenAuras is %s, update both.'], OPTIONS, tostring(version), tostring(addonVersion)))
    end
    return true
end

---@param pageId string?
---@param context table? { tabId, itemKey } inside that page
function NRSKNUI:OpenOptions(pageId, context)
    -- loading builds the whole window, which waits until combat is over
    if InCombatLockdown() then
        self:Print(L['Options will open after combat ends.'])
        self:RunWhenSafe(function()
            self:OpenOptions(pageId, context)
        end)
        return
    end
    if not LoadOptions() then return end

    local window = self.CDMWindow
    if not window:IsShown() then
        window:Show()
    end
    if pageId then
        window:ShowPage(pageId, context)
    end
end

function NRSKNUI:ToggleOptions()
    local window = self.CDMWindow
    if window and window:IsShown() then
        window:Hide()
    else
        self:OpenOptions()
    end
end

SLASH_NORSKENAURAS1 = '/nauras'
SlashCmdList.NORSKENAURAS = function(input)
    local command = strlower(strtrim(input or ''))
    if command == 'reset' then
        NRSKNUI.db.global.GUIState = { frame = {} }
        if NRSKNUI.CDMWindow then
            NRSKNUI.CDMWindow:ResetPosition()
        end
        return
    end

    NRSKNUI:ToggleOptions()
end

function _G.NorskenAuras_OnCompartmentClick()
    NRSKNUI:ToggleOptions()
end
