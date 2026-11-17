---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
local Apply = NRSKNUI.Enum.Apply
local L = NRSKNUI.Libs.AL
local Theme = NRSKNUI.Theme
local IconPicker = NRSKNUI.CDMIconPicker
local rowH = Theme.rowHeight

local tostring = tostring
local tonumber = tonumber

---@class NRSKNUI.CDMDisplayTab
local DisplayTab = NRSKNUI.CDMDisplayTab
local ICON_SOURCES = DisplayTab.ICON_SOURCES

---Where an icon's art comes from: its trigger's, or one picked by hand.
---@param card table
---@param page table
---@param style table read side
---@param set fun(path: string[], value: any, part: NorskenCore.Apply)
---@param mixed fun(path: (string|number)[], default: any?): KajiGUIMixedEntry[]?
---@param refreshTree fun() the sidebar shows the icon too
function DisplayTab.IconSourceRows(card, page, style, set, mixed, refreshTree)
    local sourceRow = card:Row(rowH)
    sourceRow:Dropdown(L['Icon Source'], {
        width = 0.5,
        conditions = { 'cdm:icon' },
        options = ICON_SOURCES,
        value = style.IconSource,
        mixed = mixed({ 'IconSource' }),
        callback = function(value)
            set({ 'IconSource' }, value, Apply.Look)
            refreshTree()
            page:Refresh()
        end,
    })
    sourceRow:EditBox(L['Manual Icon'], {
        width = 'fill',
        conditions = { 'cdm:icon' },
        tooltip = L['An icon file ID. Automatic uses it for triggers without an icon of their own, such as Player Stat.'],
        value = style.ManualIcon and tostring(style.ManualIcon) or '',
        mixed = mixed({ 'ManualIcon' }),
        callback = function(text)
            set({ 'ManualIcon' }, tonumber(text), Apply.Look)
            refreshTree()
        end,
    })
    IconPicker:BrowseButton(sourceRow, style.ManualIcon, function()
        IconPicker:Open(style.ManualIcon, function(texture)
            set({ 'ManualIcon' }, texture, Apply.Look)
            refreshTree()
        end)
    end, { 'cdm:icon' })
end
