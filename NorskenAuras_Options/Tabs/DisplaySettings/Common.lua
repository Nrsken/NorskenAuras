---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local L = NRSKNUI.Libs.AL

local ipairs = ipairs

local ICON_SOURCES = {
    { value = 'auto',   text = L['Automatic'] },
    { value = 'manual', text = L['Manual'] },
}

-- the CDM's own sections that start open, beside the shared ones
for _, key in ipairs({ 'bar', 'groupIcon', 'groupAnchor', 'size:bar', 'size:text' }) do
    NRSKNUI.GUIAuraLook.sectionOpen[key] = true
end

---@class NRSKNUI.CDMDisplayTab
local DisplayTab = {}

NRSKNUI.CDMDisplayTab = DisplayTab

---A trigger whose %p is a value (Power, Player Stat), not a time
---@param trigger CDMTrigger
---@return boolean
function DisplayTab.IsValueTrigger(trigger)
    return CDM.TriggerTypes[trigger.Type].Value == true
end

DisplayTab.ICON_SOURCES = ICON_SOURCES
