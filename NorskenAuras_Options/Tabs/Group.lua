---@class NRSKNUI
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local L = NRSKNUI.Libs.AL
local Theme = NRSKNUI.Theme
local IconPicker = NRSKNUI.CDMIconPicker
local AuraCards = NRSKNUI.GUIAuraCards
local rowH = Theme.rowHeight
local rowHL = Theme.rowHeightLast

local tostring = tostring
local tonumber = tonumber

local Shared = NRSKNUI.CDMOptions
local Applier = Shared.Applier
local PositionConfig = Shared.PositionConfig
local RefreshTree = Shared.RefreshTree

local ANCHOR_ROLES = {
    { value = 'none',      text = L['None'] },
    { value = 'primary',   text = L['Primary'] },
    { value = 'secondary', text = L['Secondary'] },
}

local function ScheduleAnchorUpdate()
    CDM:SendMessage('NRSKNUI_CDM_LAYOUT_CHANGED')
end

---@param page table
---@param id string
local function BuildGroupTab(page, id)
    local display = CDM:Get(id)
    local apply = Applier(id)
    local Section = NRSKNUI.CDMDisplayTab.Section
    local dynamic = display.type == 'dynamicgroup'
    local auraGroup = display.type == 'auragroup'
    local grow = (dynamic or auraGroup) and display.Layout.Grow

    page:Card(L['Group'], 'all'):Rebuild(function(card)
        if Section(card, 'groupIcon', L['Group Icon']) then
            local iconRow = card:Row(rowH)
            iconRow:EditBox(L['Icon ID'], {
                width = 'fill',
                tooltip = auraGroup and L['The icon this aura group shows in the list. Empty uses its first spell.']
                    or L['The icon this group shows in the list. Empty uses its first icon.'],
                value = display.Icon and tostring(display.Icon) or '',
                callback = function(text)
                    display.Icon = tonumber(text)
                    RefreshTree()
                end,
            })
            IconPicker:BrowseButton(iconRow, display.Icon, function()
                IconPicker:Open(display.Icon, function(texture)
                    display.Icon = texture
                    RefreshTree()
                end)
            end)
        end

        if (dynamic or auraGroup) and Section(card, 'groupLayout', L['Dynamic Group Settings']) then
            card:Premade('DynamicGroupCard', {
                db = display.Layout,
                showLimit = dynamic,
                -- the game sorts an aura group's auras and caps each trigger on its own
                extraRows = auraGroup and function(c)
                    local function Set(key)
                        return function(value)
                            display[key] = value
                            apply()
                        end
                    end

                    local sortRow = c:Row(rowH)
                    sortRow:Dropdown(L['Sort Method'], { width = 0.5, options = AuraCards.SortMethods, value = display.sortMethod, callback = Set('sortMethod') })
                    sortRow:Dropdown(L['Sort Direction'], { width = 0.5, options = AuraCards.SortDirections, value = display.sortDirection, callback = Set('sortDirection') })

                    local countRow = c:Row(rowHL, 0)
                    countRow:Slider(L['Auras Per Trigger'], {
                        width = 0.5,
                        tooltip = L['Each trigger shows up to this many, so several triggers can show more in total.'],
                        min = 1,
                        max = 40,
                        step = 1,
                        value = display.maxFrameCount,
                        callback = Set('maxFrameCount'),
                    })
                    countRow:Slider(L['Preview Limit'], {
                        width = 0.5,
                        tooltip = L['How many auras the preview and the mover box show. The real auras are left alone.'],
                        min = 1,
                        max = 40,
                        step = 1,
                        value = display.previewLimit,
                        callback = Set('previewLimit'),
                    })
                end or nil,
                -- a chained group never reads the limit; asked on every rebuild, as switching to Grid lifts it
                limitNotice = function()
                    return CDM:WantsChain(id) and {
                        level = 'info',
                        title = L['Limit Information'],
                        text = L["Auras and texts are secret, so we can't count how many are showing. Use Grid if you need a limit."],
                    } or nil
                end,
                onChangeCallback = function()
                    -- a picked point belongs to the direction it was picked for
                    if display.Layout.Grow ~= grow then
                        grow = display.Layout.Grow
                        display.Position.SelfPoint = nil
                    end
                    apply()
                end,
            })
        end

        if dynamic and Section(card, 'groupAnchor', L['Unit Frame Anchor']) then
            card:Row(rowH):Dropdown(L['Anchor Role'], {
                width = 1,
                options = ANCHOR_ROLES,
                value = display.UFAnchor or 'none',
                tooltip = L['The unit frame anchor follows the loaded group with this role. Give one group per class or spec the Primary role.'],
                callback = function(value)
                    display.UFAnchor = value ~= 'none' and value or nil
                    ScheduleAnchorUpdate()
                end,
            })
        end

        if Section(card, 'groupPosition', L['Position and Size Settings']) then
            card:Premade('PositionCard', PositionConfig(id))
        end
    end)
end

Shared.BuildGroupTab = BuildGroupTab
Shared.ScheduleAnchorUpdate = ScheduleAnchorUpdate
