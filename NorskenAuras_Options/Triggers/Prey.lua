---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local Apply = NRSKNUI.Enum.Apply
local L = NRSKNUI.Libs.AL

local Shared = NRSKNUI.CDMOptions
local TriggerRows = Shared.TriggerRows
local TextCodes = Shared.TextCodes

TextCodes.prey = {
    n = L['Hunt text'],
    i = L['Prey icon'],
    tips = { n = L['The title, heat or hint, as its Text option picks.'] },
}

local HUNT_TEXTS = Shared.ChoiceOptions(CDM.HUNT_TEXTS, {
    title = L['Quest Title'],
    state = L['Progress State'],
    hint  = L['Hunt Hint'],
})

---@param typeRow KajiGUIFluentRow
---@param trigger CDMTrigger
---@param apply fun(part: NorskenCore.Apply)
function TriggerRows.prey(_, typeRow, _, trigger, _, apply)
    typeRow:Dropdown(L['Text'], {
        width = 1,
        tooltip = L['What %n shows. The state and hint are only known inside the hunt zone.'],
        options = HUNT_TEXTS,
        value = trigger.Text,
        callback = function(value)
            trigger.Text = value
            apply(Apply.All)
        end,
    })
end
