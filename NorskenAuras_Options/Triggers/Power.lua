---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local Apply = NRSKNUI.Enum.Apply
local L = NRSKNUI.Libs.AL
local Theme = NRSKNUI.Theme
local rowH = Theme.rowHeight

local ipairs = ipairs
local format = string.format

local Shared = NRSKNUI.CDMOptions
local CatalogueOptions = Shared.CatalogueOptions
local TriggerRows = Shared.TriggerRows
local TextCodes = Shared.TextCodes

TextCodes.power = {
    p = L['Value'],
    t = L['Max'],
    n = L['Power name'],
}

-- What each of CDM.POWER_MODES is called here, %s in its tooltip is the resource
local MODE_LABELS = {
    bar      = { text = L['Static Single Bar'],   tooltip = L['One bar for all your %s.'] },
    static   = { text = L['Static Segments'],     tooltip = L['One segment each, filled while it is ready, empty otherwise.'] },
    progress = { text = L['Recharging Segments'], tooltip = L['Like Static Segments but each one fills up as it recharges.'] },
}

---@param card KajiGUIFluentCard
---@param typeRow KajiGUIFluentRow
---@param display CDMDisplay
---@param trigger CDMTrigger
---@param id string
---@param apply fun(part: NorskenCore.Apply)
function TriggerRows.power(card, typeRow, display, trigger, id, apply)
    typeRow:Dropdown(L['Power Type'], {
        width = 0.5,
        tooltip = L['Primary Power follows your form and spec.'],
        options = CDM.POWER_TYPES,
        value = trigger.PowerType,
        callback = function(value)
            trigger.PowerType = value
            if not CDM.SEGMENTED_POWER[trigger.PowerType] then
                trigger.Mode = 'bar'
            end
            if trigger.PowerType == CDM.MAELSTROM_WEAPON and trigger.Mode == 'progress' then trigger.Mode = 'static' end
            apply(Apply.All)
            card:Rebuild()
        end,
    })
    if display.type ~= 'bar' or not CDM.SEGMENTED_POWER[trigger.PowerType] then return end

    local Power = Enum.PowerType
    local pType = trigger.Mode == 'progress' and trigger.PowerType ~= Power.Runes and trigger.PowerType ~= Power.Essence

    local modes = {}
    for _, value in ipairs(CDM.POWER_MODES) do
        -- A stack has no partial fill to show
        if not (value == 'progress' and trigger.PowerType == CDM.MAELSTROM_WEAPON) then
            local label = MODE_LABELS[value]
            modes[#modes + 1] = { value = value, text = label.text, tooltip = format(label.tooltip, CDM.POWER_NAMES[trigger.PowerType]) }
        end
    end
    local row = card:Row(rowH)
    row:Dropdown(L['Mode'], {
        width = pType and 0.5 or 1,
        options = modes,
        value = trigger.Mode,
        callback = function(value)
            trigger.Mode = value
            apply(Apply.All)
            card:Rebuild()
        end,
    })
    if pType then
        local sources = { { value = 0, text = L['None'] } }
        for _, option in ipairs(CatalogueOptions({ Enum.CooldownViewerCategory.TrackedBar })) do sources[#sources + 1] = option end
        row:Dropdown(L['Progress Source'], {
            width = 0.5,
            tooltip = format(L['A Cooldown Manager bar that fills the next %s, like Crusading Strikes.'], CDM.PIP_NAMES[trigger.PowerType]),
            options = sources,
            value = trigger.ProgressCooldownID or 0,
            callback = function(value)
                trigger.ProgressCooldownID = value ~= 0 and value or nil
                apply(Apply.All)
            end,
        })
    end
end
