---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local Apply = NRSKNUI.Enum.Apply
local L = NRSKNUI.Libs.AL

local ipairs = ipairs

local Shared = NRSKNUI.CDMOptions
local TriggerRows = Shared.TriggerRows
local TextCodes = Shared.TextCodes

TextCodes.stat = {
    p = L['Percent'],
    t = L['Rating'],
    n = L['Stat name'],
}

---@param card KajiGUIFluentCard
---@param typeRow KajiGUIFluentRow
---@param display CDMDisplay
---@param trigger CDMTrigger
---@param id string
---@param apply fun(part: NorskenCore.Apply)
function TriggerRows.stat(card, typeRow, display, trigger, id, apply)
    local options = {}
    for _, stat in ipairs(CDM.STATS) do options[#options + 1] = { value = stat.key, text = stat.name } end
    typeRow:Dropdown(L['Stat'], {
        width = 1,
        tooltip = L['%p is the percent, %t the rating, as the character sheet shows them. Versatility is its rating part.'],
        options = options,
        value = trigger.Stat,
        callback = function(value)
            trigger.Stat = value
            apply(Apply.All)
        end,
    })
end
