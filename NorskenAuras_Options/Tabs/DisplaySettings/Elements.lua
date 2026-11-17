---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local Apply = NRSKNUI.Enum.Apply
local L = NRSKNUI.Libs.AL
local Theme = NRSKNUI.Theme
local rowH = Theme.rowHeight

local ipairs = ipairs
local min = math.min
local tsort = table.sort

---@class NRSKNUI.CDMDisplayTab
local DisplayTab = NRSKNUI.CDMDisplayTab
local AuraLook = NRSKNUI.GUIAuraLook
local Section = AuraLook.Section
local SplitPower = DisplayTab.SplitPower

local TICK_PLACEMENTS = {
    { value = 'auto',    text = L['Automatic'] },
    { value = 'value',   text = L['At Value'] },
    { value = 'percent', text = L['At Percent'] },
}

local GLOW_TYPES = {
    { value = 'pixel',    text = L['Pixel Glow'] },
    { value = 'button',   text = L['Action Button Glow'] },
    { value = 'autocast', text = L['Auto-Cast Shine'] },
    { value = 'gcd',      text = L['GCD Glow'] },
    { value = 'modern',   text = L['Modern WoW Glow'] },
    { value = 'classic',  text = L['Classic WoW Glow'] },
}

local GLOW_COLOR_MODES = {
    { value = 'default', text = L['Default'] },
    { value = 'class',   text = L['Class Color'] },
    { value = 'custom',  text = L['Custom'] },
}

-- Sections --

---@param card table
---@param page table
---@param element table read side
---@param set fun(path: string[], value: any, part: NorskenCore.Apply)
---@param mixed fun(path: (string|number)[], default: any?): KajiGUIMixedEntry[]? where the displays edited together disagree (AuraLook.Differ)
---@param key string
local function TickRows(card, page, element, set, mixed, key)
    local shown, placed, manualLength = key .. ':shown', key .. ':placed', key .. ':length'
    local function on() return element.Enabled == true or mixed({ 'Enabled' }) end
    page:SetCondition(shown, on)
    page:SetCondition(placed, function() return on() and (element.Placement ~= 'auto' or mixed({ 'Placement' })) end)
    page:SetCondition(manualLength, function() return on() and (not element.AutoLength or mixed({ 'AutoLength' })) end)

    local showRow = card:Row(rowH)
    showRow:Checkbox(L['Show Tick'], {
        width = 0.5,
        value = element.Enabled,
        mixed = mixed({ 'Enabled' }),
        callback = function(checked)
            set({ 'Enabled' }, checked, Apply.Visibility)
            page:Refresh()
        end,
    })
    showRow:ColorPicker(L['Tick Color'], {
        width = 0.5,
        conditions = { shown },
        value = element.Color,
        mixed = mixed({ 'Color' }),
        callback = function(r, g, b, a) set({ 'Color' }, { r, g, b, a }, Apply.Color) end,
    })

    local placeRow = card:Row(rowH)
    placeRow:Dropdown(L['Placement'], {
        width = 0.5,
        conditions = { shown },
        tooltip = L['Automatic splits combo points, chi and other point resources into segments, and marks channel ticks and empower stages. At Value counts power, or seconds into a cast.'],
        options = TICK_PLACEMENTS,
        value = element.Placement,
        mixed = mixed({ 'Placement' }),
        callback = function(value)
            set({ 'Placement' }, value, Apply.Layout)
            page:Refresh()
        end,
    })
    placeRow:EditBox(L['Placements'], {
        width = 0.5,
        conditions = { placed },
        tooltip = L['One or more values, comma separated.'],
        value = element.Placements,
        mixed = mixed({ 'Placements' }),
        callback = function(text) set({ 'Placements' }, text, Apply.Layout) end,
    })

    local sizeRow = card:Row(rowH)
    sizeRow:Slider(L['Thickness'], {
        width = 0.5,
        conditions = { shown },
        min = 1,
        max = 10,
        step = 1,
        value = element.Thickness,
        mixed = mixed({ 'Thickness' }),
        callback = function(value) set({ 'Thickness' }, value, Apply.Layout) end,
    })
    sizeRow:Checkbox(L['Automatic Length'], {
        width = 0.5,
        conditions = { shown },
        tooltip = L['Spans the whole bar.'],
        value = element.AutoLength,
        mixed = mixed({ 'AutoLength' }),
        callback = function(checked)
            set({ 'AutoLength' }, checked, Apply.Layout)
            page:Refresh()
        end,
    })
    card:Row(rowH):Slider(L['Length'], {
        width = 0.5,
        conditions = { manualLength },
        min = 1,
        max = 100,
        step = 1,
        value = element.Length,
        mixed = mixed({ 'Length' }),
        callback = function(value) set({ 'Length' }, value, Apply.Layout) end,
    })
end

-- A glow is hidden until a condition shows it, so its settings stay editable while Show Glow is off.
---@param card table
---@param element table
---@param set fun(path: string[], value: any, part: NorskenCore.Apply)
---@param mixed fun(path: (string|number)[], default: any?): KajiGUIMixedEntry[]? where the displays edited together disagree (AuraLook.Differ)
local function GlowRows(card, element, set, mixed)
    card:Row(rowH):Checkbox(L['Show Glow'], {
        width = 1,
        tooltip = L['Shows the glow all the time. Leave it off and let a condition show it, like Proc Glow.'],
        value = element.Enabled,
        mixed = mixed({ 'Enabled' }),
        callback = function(checked) set({ 'Enabled' }, checked, Apply.Visibility) end,
    })

    local typeRow = card:Row(rowH)
    typeRow:Dropdown(L['Glow Type'], {
        width = 0.5,
        options = GLOW_TYPES,
        value = element.Type,
        mixed = mixed({ 'Type' }),
        callback = function(value)
            set({ 'Type' }, value, Apply.Look)
            card:Rebuild()
        end,
    })
    typeRow:Dropdown(L['Glow Color'], {
        width = 0.5,
        options = GLOW_COLOR_MODES,
        value = element.ColorMode,
        mixed = mixed({ 'ColorMode' }),
        callback = function(value)
            set({ 'ColorMode' }, value, Apply.Color)
            card:Rebuild()
        end,
    })
    if element.ColorMode == 'custom' or mixed({ 'ColorMode' }) then
        card:Row(rowH):ColorPicker(L['Color'], {
            width = 0.5,
            value = element.Color,
            mixed = mixed({ 'Color' }),
            callback = function(r, g, b, a) set({ 'Color' }, { r, g, b, a }, Apply.Color) end,
        })
    end

    if element.Type == 'pixel' or mixed({ 'Type' }) then
        card:Row(rowH):Slider(L['Speed'], {
            width = 0.5,
            min = 0.05,
            max = 1,
            step = 0.05,
            value = element.Frequency,
            mixed = mixed({ 'Frequency' }),
            callback = function(value) set({ 'Frequency' }, value, Apply.Look) end,
        })
        local linesRow = card:Row(rowH)
        linesRow:Slider(L['Lines'], {
            width = 0.5,
            min = 1,
            max = 16,
            step = 1,
            value = element.Lines,
            mixed = mixed({ 'Lines' }),
            callback = function(value) set({ 'Lines' }, value, Apply.Look) end,
        })
        linesRow:Slider(L['Length'], {
            width = 0.5,
            min = 1,
            max = 20,
            step = 1,
            value = element.Length,
            mixed = mixed({ 'Length' }),
            callback = function(value) set({ 'Length' }, value, Apply.Look) end,
        })
        local sizeRow = card:Row(rowH)
        sizeRow:Slider(L['Thickness'], {
            width = 0.5,
            min = 1,
            max = 8,
            step = 1,
            value = element.Thickness,
            mixed = mixed({ 'Thickness' }),
            callback = function(value) set({ 'Thickness' }, value, Apply.Look) end,
        })
        sizeRow:Checkbox(L['Border'], {
            width = 0.5,
            tooltip = L['A dark band behind the lines.'],
            value = element.Border ~= false,
            mixed = mixed({ 'Border' }, true),
            callback = function(checked) set({ 'Border' }, checked, Apply.Look) end,
        })
    end

    if element.Type == 'modern' or mixed({ 'Type' }) then
        card:Row(rowH):Checkbox(L['Start Animation'], {
            width = 0.5,
            tooltip = L["Plays Blizzard's proc burst when the glow starts."],
            value = element.StartAnim ~= false,
            mixed = mixed({ 'StartAnim' }, true),
            callback = function(checked) set({ 'StartAnim' }, checked, Apply.Look) end,
        })
    end
end

-- Sub elements --

---The shared sub element list plus the CDM's own: glows, ticks, aura overlays between rows,
---pips and the conditions that point at elements by index.
---@param card table
---@param page table
---@param icons table[]
---@param apply fun(part: NorskenCore.Apply)
---@param triggerChip fun(index: number, trigger: table): string
local function SubElements(card, page, icons, apply, triggerChip)
    local first = icons[1]
    local count = #first.SubRegions
    local powerType
    for _, display in ipairs(icons) do
        powerType = powerType or SplitPower(display)
    end

    -- The overlays sit in the list at their slot (one icon only: slots differ per icon), listed bottom layer first like the elements.
    local overlays = {}
    if #icons == 1 then
        for i, trigger in ipairs(first.Triggers) do
            if trigger.Type == 'auraoverlay' then
                overlays[#overlays + 1] = i
            end
        end
    end
    local function SlotOf(i) return min(first.Triggers[i].Slot or 0, count) end
    tsort(overlays, function(a, b)
        if SlotOf(a) ~= SlotOf(b) then return SlotOf(a) < SlotOf(b) end
        return a > b -- an earlier trigger draws on top, so it lists after
    end)
    local function Move(i, by)
        first.Triggers[i].Slot = SlotOf(i) + by
        apply(Apply.Look)
        card:Rebuild()
    end

    local adds = { { 'text', L['Add Text'] }, { 'border', L['Add Border'] }, { 'glow', L['Add Glow'] } }
    if first.type == 'bar' then
        adds[#adds + 1] = { 'tick', L['Add Tick'] }
    elseif first.type == 'auragroup' then
        adds[#adds + 1] = { 'auratype', L['Add Aura Type Texture'] }
    end

    AuraLook.SubElements(card, page, icons, apply, {
        adds = adds,
        pipName = CDM.PIP_NAMES[powerType or false],
        isValue = DisplayTab.IsValueTrigger,
        dropped = CDM:DroppedAuraTexts(first),
        rows = function(_, _, element, set, mixed, key)
            if element.type == 'glow' then
                GlowRows(card, element, set, mixed)
            elseif element.type == 'tick' then
                TickRows(card, page, element, set, mixed, key)
            end
        end,
        remap = function(display, remap, index, by)
            CDM:RemapConditionSubRegions(display, remap)
            -- a copied or removed element moves the overlays' slots along
            for _, trigger in ipairs(by and display.Triggers or {}) do
                if trigger.Type == 'auraoverlay' and (trigger.Slot or 0) >= index then
                    trigger.Slot = trigger.Slot + by
                end
            end
        end,
        overlays = {
            rows = function(slot)
                for _, i in ipairs(overlays) do
                    if SlotOf(i) == slot and Section(card, 'cdm:overlay:' .. i, L['Aura Overlay'], {
                            summary = triggerChip(i, first.Triggers[i]),
                            onMoveUp = slot > 0 and function() Move(i, -1) end or nil,
                            onMoveDown = slot < count and function() Move(i, 1) end or nil,
                        }) then
                        card:Row(rowH):Text(nil, { width = 1, text = L['Rows above draw under its Aura Icon.'], bgMode = 'hide' })
                    end
                end
            end,
            -- the overlay row right above or below an element, which a move of that element crosses instead of swapping
            adjacent = function(slot, closestFirst)
                local found
                for _, i in ipairs(overlays) do
                    if SlotOf(i) == slot and not (closestFirst and found) then
                        found = i
                    end
                end
                return found
            end,
            move = Move,
        },
    })
end

DisplayTab.SubElements = SubElements
