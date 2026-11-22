---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local Apply = NRSKNUI.Enum.Apply
local L = NRSKNUI.Libs.AL
local Theme = NRSKNUI.Theme
local rowH = Theme.rowHeight

local Shared = NRSKNUI.CDMOptions
local SpellList = NRSKNUI.GUISpellList
local TriggerRows = Shared.TriggerRows
local TextCodes = Shared.TextCodes

TextCodes.cast = {
    p = L['Cast time left'],
    t = L['Cast time'],
    n = L['Spell being cast'],
    i = L["First spell's icon"],
}

local CAST_MODES = Shared.ChoiceOptions(CDM.CAST_MODES, {
    all      = L['All Casts'],
    specific = L['Specific Casts'],
})

---@param card KajiGUIFluentCard
---@param typeRow KajiGUIFluentRow
---@param display CDMDisplay
---@param trigger CDMTrigger
---@param id string
---@param apply fun(part: NorskenCore.Apply)
function TriggerRows.cast(card, typeRow, display, trigger, id, apply)
    typeRow:Dropdown(L['Casts'], {
        width = 0.5,
        options = CAST_MODES,
        value = trigger.Casts,
        callback = function(value)
            trigger.Casts = value
            apply(Apply.All)
            card:Rebuild()
        end,
    })

    -- The list is kept while on all casts, so switching back finds it again
    if trigger.Casts == 'specific' then
        local source = SpellList:ArraySource(trigger, function() return trigger.SpellIDs or {} end, function(ids)
            trigger.SpellIDs = ids[1] and ids or nil
        end, function()
            apply(Apply.All)
            card:Rebuild()
        end)
        SpellList:BuildAdd(card, source)
        SpellList:BuildList(card, source)
        -- the list ends flush, so the rule brings its own gap; inSection keeps it in the trigger's section
        card:Separator(nil, { inSection = true, height = 16 })
    end

    local row = card:Row(rowH)
    row:Slider(L['Hold Time'], {
        width = 0.5,
        tooltip = L['Keep the bar up this long after the cast ends, for the Succeeded / Interrupted / Failed conditions. 0 hides it at once.'],
        min = 0,
        max = 3,
        step = 0.1,
        value = trigger.HoldTime,
        callback = function(value)
            trigger.HoldTime = value
            apply(Apply.All)
        end,
    })
    row:Checkbox(L['Show Latency'], {
        width = 0.5,
        tooltip = L['Shades the end of the bar by the time your cast took to reach the server. Its color is on the Display tab.'],
        value = trigger.ShowLatency,
        callback = function(checked)
            trigger.ShowLatency = checked
            apply(Apply.All)
        end,
    })
end
