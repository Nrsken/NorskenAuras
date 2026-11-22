---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
local L = NRSKNUI.Libs.AL

local Shared = NRSKNUI.CDMOptions
local CatalogueOptions = Shared.CatalogueOptions
local CataloguePicker = Shared.CataloguePicker
local TriggerRows = Shared.TriggerRows
local TextCodes = Shared.TextCodes

-- Its time is secret, so only the bar follows it
TextCodes.viewerbar = {
    n = L['Spell name'],
    i = L['Spell icon'],
}

---@param card KajiGUIFluentCard
---@param typeRow KajiGUIFluentRow
---@param display CDMDisplay
---@param trigger CDMTrigger
---@param id string
---@param apply fun(part: NorskenCore.Apply)
function TriggerRows.viewerbar(card, typeRow, display, trigger, id, apply)
    typeRow:Dropdown(L['Cooldown Manager'], {
        width = 0.5,
        tooltip = L['A Tracked Bar from the Cooldown Manager, mirrored onto this bar. For entries that are not real auras, like Crusading Strikes.'],
        options = CatalogueOptions({ Enum.CooldownViewerCategory.TrackedBar }),
        value = trigger.CooldownID,
        callback = CataloguePicker(trigger, display, id, apply),
    })
end
