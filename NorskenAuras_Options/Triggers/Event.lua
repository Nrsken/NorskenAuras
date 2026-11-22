---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local Apply = NRSKNUI.Enum.Apply
local L = NRSKNUI.Libs.AL
local Theme = NRSKNUI.Theme
local rowH = Theme.rowHeight

local Shared = NRSKNUI.CDMOptions
local TriggerRows = Shared.TriggerRows

local EVENTS = Shared.ChoiceOptions(CDM.EVENTS, CDM.EVENT_NAMES)
local EVENT_UNITS = Shared.ChoiceOptions(CDM.EVENT_UNITS, {
    group  = L['Group'],
    player = L['Player'],
})

function TriggerRows.event(card, typeRow, _, trigger, _, apply)
    typeRow:Dropdown(L['Event'], {
        width = 0.5,
        options = EVENTS,
        value = trigger.Event,
        callback = function(value)
            trigger.Event = value
            apply(Apply.All)
            card:Rebuild()
        end,
    })
    local durationRow = card:Row(rowH)
    durationRow:Slider(L['Duration'], {
        width = 0.5,
        tooltip = L['How long it shows after the event.'],
        min = 0.5,
        max = 60,
        step = 0.5,
        value = trigger.Duration,
        callback = function(value)
            trigger.Duration = value
            apply(Apply.All)
        end,
    })
    if trigger.Event ~= 'unitDied' then
        durationRow:Checkbox(L['Encounter Combat'], {
            width = 0.5,
            tooltip = L['A boss fight counts as combat from its start to its end, so leaving combat inside one is ignored.'],
            value = trigger.EncounterCombat,
            callback = function(checked)
                trigger.EncounterCombat = checked
                apply(Apply.All)
            end,
        })
        local entering = trigger.Event == 'enterCombat'
        card:Row(rowH):Checkbox(entering and L['Hide on Leave'] or L['Hide on Enter'], {
            width = 0.5,
            tooltip = entering and L['Hides when combat ends.'] or L['Hides when combat starts.'],
            value = trigger.EndOnOpposite,
            callback = function(checked)
                trigger.EndOnOpposite = checked
                apply(Apply.All)
            end,
        })
        return
    end

    durationRow:Dropdown(L['Unit'], {
        width = 0.5,
        tooltip = L['Group is everyone in your party or raid but you.'],
        options = EVENT_UNITS,
        value = trigger.Unit,
        callback = function(value)
            trigger.Unit = value
            apply(Apply.All)
            card:Rebuild()
        end,
    })
    if trigger.Unit ~= 'group' then return end

    local limitRow = card:Row(rowH)
    limitRow:Slider(L['Deaths Shown'], {
        width = 0.5,
        tooltip = L['A wipe kills many at once, so only this many show inside the window.'],
        min = 1,
        max = 40,
        step = 1,
        value = trigger.DeathLimit,
        callback = function(value)
            trigger.DeathLimit = value
            apply(Apply.All)
        end,
    })
    limitRow:Slider(L['Window'], {
        width = 0.5,
        min = 1,
        max = 60,
        step = 1,
        value = trigger.DeathWindow,
        callback = function(value)
            trigger.DeathWindow = value
            apply(Apply.All)
        end,
    })
end
