---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local Apply = NRSKNUI.Enum.Apply
local L = NRSKNUI.Libs.AL

local Shared = NRSKNUI.CDMOptions
local TriggerRows = Shared.TriggerRows
local TextCodes = Shared.TextCodes

TextCodes.lootSpec = {
    n = L['Loot specialization'],
    i = L['Its icon'],
}

local CURRENT_SPEC = Shared.ChoiceOptions(CDM.CURRENT_SPEC, {
    any     = L['Any'],
    current = L['Current Spec'],
    other   = L['Not Current Spec'],
})

---@param typeRow KajiGUIFluentRow
---@param trigger CDMTrigger
---@param apply fun(part: NorskenCore.Apply)
function TriggerRows.lootSpec(_, typeRow, _, trigger, _, apply)
    typeRow:Dropdown(L['Loot Specialization'], {
        width = 0.5,
        multiSelect = true,
        tooltip = L['Active while the loot specialization is one of these. None picked is any.'],
        options = NRSKNUI.CDMConditionsTab.SELECT_OPTIONS.spec,
        value = trigger.SpecIDs,
        callback = function(value)
            trigger.SpecIDs = value
            apply(Apply.All)
        end,
    })

    typeRow:Dropdown(L['Current Specialization'], {
        width = 0.5,
        tooltip = L['Whether loot goes to the spec you are playing. Loot set to Current Specialization always is.'],
        options = CURRENT_SPEC,
        value = trigger.CurrentSpec,
        callback = function(value)
            trigger.CurrentSpec = value
            apply(Apply.All)
        end,
    })
end
