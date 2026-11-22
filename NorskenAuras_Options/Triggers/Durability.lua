---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local Apply = NRSKNUI.Enum.Apply
local L = NRSKNUI.Libs.AL

local Shared = NRSKNUI.CDMOptions
local TriggerRows = Shared.TriggerRows
local TextCodes = Shared.TextCodes

TextCodes.durability = {
    p = L['Lowest percent'],
    t = L['Always 100'],
    n = L['Durability'],
}

local SHOW_ON = Shared.ChoiceOptions(CDM.DURABILITY_SHOW_ON, {
    always = L['Always'],
    value  = L['At Value'],
})

---@param card KajiGUIFluentCard
---@param typeRow KajiGUIFluentRow
---@param trigger CDMTrigger
---@param apply fun(part: NorskenCore.Apply)
function TriggerRows.durability(card, typeRow, _, trigger, _, apply)
    local ConditionsTab = NRSKNUI.CDMConditionsTab
    typeRow:Dropdown(L['Show'], {
        width = 0.5,
        tooltip = L['At Value shows it only while the lowest durability passes the check.'],
        options = SHOW_ON,
        value = trigger.ShowOn,
        callback = function(value)
            trigger.ShowOn = value
            apply(Apply.Visibility)
            card:Rebuild()
        end,
    })
    if trigger.ShowOn ~= 'value' then return end

    typeRow:Dropdown(nil, {
        width = 0.15,
        options = ConditionsTab.OPERATORS,
        value = trigger.Operator,
        callback = function(value)
            trigger.Operator = value
            apply(Apply.Visibility)
        end,
    })
    local range = ConditionsTab.PERCENT_RANGE
    typeRow:Slider(nil, {
        width = 0.35,
        min = range.min,
        max = range.max,
        step = range.step,
        value = trigger.Threshold,
        callback = function(value)
            trigger.Threshold = value
            apply(Apply.Visibility)
        end,
    })
end
